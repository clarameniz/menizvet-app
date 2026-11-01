import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  Alert,
  KeyboardAvoidingView,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { ChoiceChip } from '@/components/design-system/choice-chip';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import {
  getOrganizationStaff,
  inviteOrganizationStaff,
  STAFF_ACCESS_DENIED,
  STAFF_INVITE_ROLES,
  type StaffInviteRole,
  type StaffInviteScope,
} from '@/data/organization-staff';
import { useStaffInvite } from '@/hooks/use-staff-invite';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import { organizationStaffHref, staffRoleLabel } from '@/lib/organization-staff';
import {
  canSendInvite,
  EMPTY_STAFF_INVITE_DRAFT,
  inviteInputFrom,
  inviteRejectionKey,
  inviteRoleHasScopeChoice,
  pendingInvitationIds,
  reconcileLostInvite,
  withInviteRole,
  withInviteScope,
  type StaffInviteDraft,
} from '@/lib/staff-invitation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

const SCOPES: readonly { scope: StaffInviteScope; labelKey: TranslationKey }[] = [
  { scope: 'ORGANIZATION', labelKey: 'staffInvite.scopeOrganization' },
  { scope: 'CLINIC', labelKey: 'staffInvite.scopeClinic' },
];
// What the chosen role means for this person; the Veterinarian line also says
// what happens after acceptance, because the invitation assigns no Clinic.
const ROLE_HELP: Record<StaffInviteRole, TranslationKey> = {
  ADMINISTRATOR: 'staffInvite.roleHelpAdministrator',
  RECEPTIONIST: 'staffInvite.roleHelpReceptionist',
  VETERINARIAN: 'staffInvite.veterinarianNextSteps',
};

export default function StaffInviteRoute() {
  const { organizationId } = useLocalSearchParams<{ organizationId: string | string[] }>();
  const id = typeof organizationId === 'string' ? organizationId : '';
  // A changed route owns a fresh draft: nothing drafted for A survives into B.
  return <StaffInviteScreen key={id} organizationId={id} />;
}

/**
 * SPEC-ORG-002 §10: one recipient, one role asked as "What will this person
 * do?" (Administrator, Receptionist or Veterinarian), one scope (the whole Organization or one of its Clinics;
 * Veterinarian is always the whole Organization, with no Clinic selector and
 * no Clinic Assignment). No Owner, no expiry, no recipient User. The backend authorizes, fixes
 * the 7-day validity and decides every value; the form only requires
 * completeness. A lost response is never retried: the Staff re-read decides.
 */
function StaffInviteScreen({ organizationId }: { organizationId: string }) {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { state, reload, leave, isActive } = useStaffInvite(organizationId);
  const [draft, setDraft] = useState<StaffInviteDraft>(EMPTY_STAFF_INVITE_DRAFT);
  const [sending, setSending] = useState(false);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);
  const busyRef = useRef(false);

  useEffect(() => {
    void reload();
  }, [reload]);

  const back = useCallback(() => {
    leave(() => goBackOr(organizationStaffHref(organizationId)));
  }, [leave, organizationId]);
  const returnToStaff = useCallback(() => {
    leave(() => {
      AccessibilityInfo.announceForAccessibility(t('staffInvite.sent'));
      router.dismissTo(organizationStaffHref(organizationId));
    });
  }, [leave, organizationId, t]);
  const loseAccess = useCallback(() => {
    leave(() => {
      Alert.alert(t('staff.title'), t('staffInvite.unavailable'));
      router.dismissTo('/professional');
    });
  }, [leave, t]);

  const update = (next: StaffInviteDraft) => {
    if (busyRef.current) return;
    setDraft(next);
    setErrorKey(null);
  };

  if (state.kind !== 'loaded') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={back} />
          {state.kind === 'loading' ? (
            <StateMessage tone="loading" message={t('staffInvite.loading')} />
          ) : (
            <View style={styles.section}>
              <StateMessage
                tone={state.kind === 'unavailable' ? 'empty' : 'error'}
                message={t(
                  state.kind === 'unavailable' ? 'staffInvite.unavailable' : state.messageKey,
                )}
              />
              {state.kind === 'error' ? (
                <Button label={t('professional.retry')} onPress={() => void reload()} />
              ) : null}
              <Button variant="secondary" label={t('staffInvite.backToStaff')} onPress={back} />
            </View>
          )}
        </View>
      </SafeAreaView>
    );
  }

  const { clinics, organizationDisplayName } = state;
  const sendEnabled = canSendInvite(draft, clinics, sending);

  async function send() {
    const input = inviteInputFrom(organizationId, draft);
    if (busyRef.current || !isActive() || !sendEnabled || input === null) return;
    busyRef.current = true;
    setSending(true);
    setErrorKey(null);
    try {
      // Freshest known pending set: a later match can only be this request's.
      const before = await getOrganizationStaff(organizationId);
      if (!isActive()) return;
      if (before.error === STAFF_ACCESS_DENIED) {
        loseAccess();
        return;
      }
      const pendingBefore =
        before.error === null
          ? pendingInvitationIds(before.data)
          : state.kind === 'loaded'
            ? state.pendingBefore
            : new Set<string>();
      const result = await inviteOrganizationStaff(input);
      if (!isActive()) return;
      if (result.kind === 'created') {
        returnToStaff();
        return;
      }
      if (result.kind === 'rejected') {
        if (result.reason === 'ORGANIZATION_UNAVAILABLE') {
          loseAccess();
          return;
        }
        setErrorKey(inviteRejectionKey(result.reason));
        // The authoritative re-read follows 409 and may withdraw a Clinic.
        const read = await reload();
        if (!isActive()) return;
        if (read?.kind === 'unavailable') loseAccess();
        else if (
          read?.kind === 'loaded' &&
          draft.clinicId !== null &&
          !read.clinics.some((clinic) => clinic.clinicId === draft.clinicId)
        )
          setDraft((current) => ({ ...current, clinicId: null }));
        return;
      }
      const after = await getOrganizationStaff(organizationId);
      if (!isActive()) return;
      const reconciliation = reconcileLostInvite(after, input, pendingBefore);
      if (reconciliation === 'created') returnToStaff();
      else if (reconciliation === 'accessLost') loseAccess();
      else
        setErrorKey(
          reconciliation === 'pendingExists'
            ? 'staffInvite.pendingExists'
            : reconciliation === 'authenticationRequired'
              ? 'errors.sessionExpired'
              : 'staffInvite.unconfirmed',
        );
    } finally {
      busyRef.current = false;
      if (isActive()) setSending(false);
    }
  }

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
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
          <AppTopBar onBack={back} />
          <Text style={styles.title} accessibilityRole="header">
            {t('staffInvite.title')}
          </Text>
          <Text style={styles.hint}>
            {t('staffInvite.intro', { organization: organizationDisplayName })}
          </Text>

          <Input
            label={t('staffInvite.emailLabel')}
            value={draft.email}
            onChangeText={(email) => update({ ...draft, email })}
            keyboardType="email-address"
            autoCapitalize="none"
            autoCorrect={false}
            autoComplete="email"
            textContentType="emailAddress"
            editable={!sending}
            required
          />

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>{t('staffInvite.roleQuestion')}</Text>
            <View style={styles.choices} accessibilityRole="radiogroup">
              {STAFF_INVITE_ROLES.map((role) => (
                <ChoiceChip
                  key={role}
                  label={staffRoleLabel(role, t)}
                  selected={draft.role === role}
                  disabled={sending}
                  onPress={() => update(withInviteRole(draft, role))}
                />
              ))}
            </View>
            {draft.role === null ? null : (
              <Text style={styles.hint}>{t(ROLE_HELP[draft.role])}</Text>
            )}
          </View>

          {draft.role === 'VETERINARIAN' ? null : (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>{t('staffInvite.scopeHeading')}</Text>
              <View style={styles.choices} accessibilityRole="radiogroup">
                {SCOPES.map(({ scope, labelKey }) => (
                  <ChoiceChip
                    key={scope}
                    label={t(labelKey)}
                    selected={draft.scope === scope}
                    disabled={sending}
                    onPress={() => update(withInviteScope(draft, scope))}
                  />
                ))}
              </View>
            </View>
          )}

          {draft.scope === 'CLINIC' && inviteRoleHasScopeChoice(draft.role) ? (
            <View style={styles.section}>
              <Text style={styles.sectionTitle}>{t('staffInvite.clinicHeading')}</Text>
              {clinics.length === 0 ? (
                <Text style={styles.hint}>{t('staffInvite.noClinics')}</Text>
              ) : (
                <View style={styles.choices} accessibilityRole="radiogroup">
                  {clinics.map((clinic) => (
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

          <Text style={styles.hint}>{t('staffInvite.moreLater')}</Text>
          <Text style={styles.hint}>{t('staffInvite.validity')}</Text>
        </ScrollView>

        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
          <Button
            label={t('staffInvite.submit')}
            onPress={() => void send()}
            loading={sending}
            disabled={!sendEnabled}
          />
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
  flex: { flex: 1 },
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

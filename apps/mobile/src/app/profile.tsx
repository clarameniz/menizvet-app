import { Ionicons } from '@expo/vector-icons';
import Constants from 'expo-constants';
import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState, type ComponentProps, type ReactNode } from 'react';
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

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { StateMessage } from '@/components/design-system/state-message';
import { getCurrentUserProfile, saveDisplayName } from '@/data/user-profile';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import type { LocalePreference } from '@/i18n/types';
import { DELETE_ACCOUNT_URL, openExternalUrl, PRIVACY_POLICY_URL } from '@/lib/external-link';
import { useSession } from '@/lib/session-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'loaded' | 'error';

type IoniconName = ComponentProps<typeof Ionicons>['name'];

const LANGUAGE_OPTIONS: readonly { value: LocalePreference; labelKey: TranslationKey }[] = [
  { value: 'system', labelKey: 'language.system' },
  { value: 'es', labelKey: 'language.spanish' },
  { value: 'en', labelKey: 'language.english' },
];

// Already-configured app version (app.config.ts), read through the existing
// expo-constants dependency — no new dependency just for this.
const APP_VERSION = Constants.expoConfig?.version ?? null;

/**
 * Authenticated-only route, pushed from (app)/index.tsx. Kept as a top-level
 * Stack.Screen (guarded the same way as (app) in the root layout), pushed
 * over (app) rather than nested inside that group — so `router.back()` (and
 * Android hardware back) always return to the authenticated home.
 *
 * Shows only real, supported account capabilities: the SPEC-ID-006 display
 * name (editable), the authenticated email (read-only — changing it is not
 * ordinary Profile editing, SPEC-ID-006 BR-6), the local language preference,
 * and the centralized `signOut()`. There is deliberately no "Change password"
 * action: authenticated password change is out of scope for SPEC-ID-006
 * (§13) and no other approved Specification defines it.
 *
 * "Privacy policy" and "Delete account" only open the public MenizVet web
 * pages in the system browser. Account deletion itself is not implemented in
 * the app: it is out of scope for SPEC-ID-004 (§6) and SPEC-ID-006 (§13) and
 * requires separate, not-yet-approved identity/retention behavior.
 *
 * Errors from public.user_profiles reads/writes are PostgREST/Postgres
 * errors with no defined user-facing taxonomy in this repository (unlike
 * Auth's stable error codes — see i18n/error-messages.ts) — so any failure
 * here always shows the single generic localized message, never the raw
 * provider text.
 */
export default function ProfileScreen() {
  const { t, preference, setPreference } = useLocale();
  const { user, signOut } = useSession();
  const email = user?.email ?? null;

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [displayName, setDisplayName] = useState('');
  const [isEditingName, setIsEditingName] = useState(false);
  const [draftName, setDraftName] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const [hasSaveError, setHasSaveError] = useState(false);
  const [savedMessage, setSavedMessage] = useState<string | null>(null);
  const [isLanguageExpanded, setIsLanguageExpanded] = useState(false);
  const [hasLinkError, setHasLinkError] = useState(false);
  const [isOpeningLink, setIsOpeningLink] = useState(false);

  useEffect(() => {
    let isMounted = true;

    getCurrentUserProfile().then(({ data, error }) => {
      if (!isMounted) return;

      if (error) {
        setLoadState('error');
        return;
      }

      // data is null when no profile row exists yet (never created because
      // the user has not saved a display name before) — an empty name is the
      // correct, normal representation of that state.
      setDisplayName(data?.displayName ?? '');
      setLoadState('loaded');
    });

    return () => {
      isMounted = false;
    };
  }, []);

  const goBack = () => router.back();

  function startEditingName() {
    setDraftName(displayName);
    setHasSaveError(false);
    setSavedMessage(null);
    setIsEditingName(true);
  }

  function cancelEditingName() {
    setHasSaveError(false);
    setIsEditingName(false);
  }

  async function handleSave() {
    if (isSaving) return;

    setHasSaveError(false);
    setSavedMessage(null);
    setIsSaving(true);

    // Empty is a valid value (clears display_name, SPEC-ID-006 BR-9/BR-10) —
    // not rejected as invalid input. No length/format check is applied
    // because SPEC-ID-006 defers exact limits to future architecture/product
    // configuration and the column itself has no such constraint; adding one
    // here would be an invented client rule, not an enforced Spec rule.
    const trimmed = draftName.trim();
    const result = await saveDisplayName(trimmed.length > 0 ? trimmed : null);

    setIsSaving(false);

    if (result.error !== null) {
      // Stay in edit mode with the draft intact so the User can retry.
      setHasSaveError(true);
      return;
    }

    // Only reflect the saved value once Supabase has confirmed the write —
    // no optimistic update before this point.
    setDisplayName(result.data.displayName ?? '');
    setIsEditingName(false);
    setSavedMessage(t('profile.saved'));
  }

  async function handleOpenLink(url: string) {
    if (isOpeningLink) return;

    setHasLinkError(false);
    setIsOpeningLink(true);
    const opened = await openExternalUrl(url);
    setIsOpeningLink(false);
    if (!opened) setHasLinkError(true);
  }

  if (loadState !== 'loaded') {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={goBack} />
          {loadState === 'loading' ? (
            <StateMessage tone="loading" message={t('profile.loading')} />
          ) : (
            <>
              <StateMessage tone="error" message={t('profile.loadError')} />
              <Button variant="secondary" label={t('common.back')} onPress={goBack} />
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  const hasDisplayName = displayName.length > 0;
  const preferenceLabel = t(
    LANGUAGE_OPTIONS.find((option) => option.value === preference)?.labelKey ?? 'language.system',
  );

  return (
    <SafeAreaView style={styles.safeArea}>
      {/* Always-light background — explicit dark status-bar icons so they
          don't inherit a previous screen's style or the OS dark-mode default. */}
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
          <AppTopBar onBack={goBack} />

          <Text style={styles.title} accessibilityRole="header">
            {t('profile.title')}
          </Text>

          <View style={styles.identity}>
            <View
              style={styles.avatar}
              accessibilityElementsHidden
              importantForAccessibility="no-hide-descendants"
            >
              <Ionicons name="person-outline" size={28} color={colors.primary} />
            </View>
            {/* With no display name yet, the email is the only identity to
                show — promoted to the primary line instead of a placeholder. */}
            <View style={styles.identityText} accessible>
              <Text style={styles.identityName} numberOfLines={2}>
                {hasDisplayName ? displayName : (email ?? t('profile.displayNameEmpty'))}
              </Text>
              {hasDisplayName && email ? (
                <Text style={styles.identityEmail} numberOfLines={1}>
                  {email}
                </Text>
              ) : null}
            </View>
          </View>

          <SettingsSection title={t('profile.sectionPersonal')}>
            {isEditingName ? (
              <View style={styles.editBlock}>
                <Input
                  label={t('profile.displayNameLabel')}
                  autoCapitalize="words"
                  autoFocus
                  value={draftName}
                  onChangeText={setDraftName}
                  editable={!isSaving}
                  returnKeyType="done"
                  onSubmitEditing={handleSave}
                />
                {hasSaveError ? <Notice tone="error" message={t('common.genericError')} /> : null}
                <View style={styles.editActions}>
                  <View style={styles.editAction}>
                    <Button
                      variant="secondary"
                      label={t('profile.cancel')}
                      onPress={cancelEditingName}
                      disabled={isSaving}
                    />
                  </View>
                  <View style={styles.editAction}>
                    <Button label={t('profile.save')} onPress={handleSave} loading={isSaving} />
                  </View>
                </View>
              </View>
            ) : (
              <SettingsRow
                icon="person-outline"
                label={t('profile.displayNameLabel')}
                value={hasDisplayName ? displayName : t('profile.displayNameEmpty')}
                isValueMuted={!hasDisplayName}
                onPress={startEditingName}
                accessibilityHint={t('profile.editNameHint')}
              />
            )}
            {email ? (
              <>
                <Divider />
                <SettingsRow icon="mail-outline" label={t('common.emailLabel')} value={email} />
              </>
            ) : null}
          </SettingsSection>

          {savedMessage ? <Notice tone="info" message={savedMessage} /> : null}

          <SettingsSection title={t('profile.sectionPreferences')}>
            <SettingsRow
              icon="language-outline"
              label={t('language.title')}
              value={preferenceLabel}
              onPress={() => setIsLanguageExpanded((expanded) => !expanded)}
              isExpanded={isLanguageExpanded}
              accessibilityHint={t('profile.languageHint')}
            />
            {isLanguageExpanded ? (
              <View accessibilityRole="radiogroup" style={styles.languageOptions}>
                {LANGUAGE_OPTIONS.map((option) => {
                  const isSelected = preference === option.value;
                  const label = t(option.labelKey);
                  return (
                    <Pressable
                      key={option.value}
                      onPress={() => {
                        setPreference(option.value);
                        setIsLanguageExpanded(false);
                      }}
                      accessibilityRole="radio"
                      accessibilityLabel={label}
                      accessibilityState={{ checked: isSelected }}
                      style={({ pressed }) => [styles.languageOption, pressed && styles.pressed]}
                    >
                      <Text
                        style={[styles.languageLabel, isSelected && styles.languageLabelSelected]}
                      >
                        {label}
                      </Text>
                      {isSelected ? (
                        <Ionicons name="checkmark" size={20} color={colors.primary} />
                      ) : null}
                    </Pressable>
                  );
                })}
              </View>
            ) : null}
          </SettingsSection>

          <SettingsSection title={t('profile.sectionAccount')}>
            <SettingsRow
              icon="shield-checkmark-outline"
              label={t('profile.privacyPolicy')}
              onPress={() => handleOpenLink(PRIVACY_POLICY_URL)}
              isExternalLink
              accessibilityHint={t('profile.externalLinkHint')}
            />
            <Divider />
            <SettingsRow
              icon="trash-outline"
              label={t('profile.deleteAccount')}
              onPress={() => handleOpenLink(DELETE_ACCOUNT_URL)}
              isExternalLink
              accessibilityHint={t('profile.externalLinkHint')}
            />
            <Divider />
            <Pressable
              onPress={() => signOut()}
              disabled={isSaving}
              accessibilityRole="button"
              accessibilityLabel={t('profile.signOut')}
              accessibilityState={{ disabled: isSaving }}
              style={({ pressed }) => [styles.row, pressed && styles.pressed]}
            >
              <View
                style={[styles.rowIcon, styles.rowIconDestructive]}
                accessibilityElementsHidden
                importantForAccessibility="no-hide-descendants"
              >
                <Ionicons name="log-out-outline" size={18} color={colors.errorDark} />
              </View>
              <Text style={styles.signOutLabel}>{t('profile.signOut')}</Text>
            </Pressable>
          </SettingsSection>

          {hasLinkError ? <Notice tone="error" message={t('profile.externalLinkError')} /> : null}

          {APP_VERSION ? (
            <Text style={styles.version}>{t('profile.appVersion', { version: APP_VERSION })}</Text>
          ) : null}
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

type SettingsSectionProps = {
  title: string;
  children: ReactNode;
};

/** One titled card of divider-separated rows. Local: only Profile uses it. */
function SettingsSection({ title, children }: SettingsSectionProps) {
  return (
    <View style={styles.section}>
      <Text style={styles.sectionTitle} accessibilityRole="header">
        {title}
      </Text>
      <View style={styles.card}>{children}</View>
    </View>
  );
}

type SettingsRowProps = {
  icon: IoniconName;
  label: string;
  value?: string;
  isValueMuted?: boolean;
  /** Omit for a read-only row: no chevron, and announced as plain text, not a button. */
  onPress?: () => void;
  /** Set for a row that expands inline (chevron rotates, `expanded` is announced). */
  isExpanded?: boolean;
  /** Set for a row that leaves the app for a web page (external icon, announced as a link). */
  isExternalLink?: boolean;
  accessibilityHint?: string;
};

function SettingsRow({
  icon,
  label,
  value,
  isValueMuted = false,
  onPress,
  isExpanded,
  isExternalLink = false,
  accessibilityHint,
}: SettingsRowProps) {
  const accessibilityLabel = value === undefined ? label : `${label}: ${value}`;
  const trailingIcon: IoniconName = isExternalLink
    ? 'open-outline'
    : isExpanded
      ? 'chevron-down'
      : 'chevron-forward';
  const content = (
    <>
      <View
        style={styles.rowIcon}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Ionicons name={icon} size={18} color={colors.primary} />
      </View>
      <Text style={styles.rowLabel}>{label}</Text>
      <Text style={[styles.rowValue, isValueMuted && styles.rowValueMuted]} numberOfLines={1}>
        {value}
      </Text>
      {onPress ? <Ionicons name={trailingIcon} size={18} color={colors.textSecondary} /> : null}
    </>
  );

  if (!onPress) {
    return (
      <View style={styles.row} accessible accessibilityLabel={accessibilityLabel}>
        {content}
      </View>
    );
  }

  return (
    <Pressable
      onPress={onPress}
      accessibilityRole={isExternalLink ? 'link' : 'button'}
      accessibilityLabel={accessibilityLabel}
      accessibilityHint={accessibilityHint}
      accessibilityState={isExpanded === undefined ? undefined : { expanded: isExpanded }}
      style={({ pressed }) => [styles.row, pressed && styles.pressed]}
    >
      {content}
    </Pressable>
  );
}

function Divider() {
  return <View style={styles.divider} />;
}

const styles = StyleSheet.create({
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
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  identity: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.lg,
  },
  avatar: {
    width: 56,
    height: 56,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  identityText: {
    flex: 1,
    gap: 2,
  },
  identityName: {
    ...typography.h3,
    color: colors.textPrimary,
  },
  identityEmail: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  section: {
    gap: spacing.sm,
  },
  sectionTitle: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  card: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    paddingHorizontal: spacing.lg,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    minHeight: 56,
    paddingVertical: spacing.sm,
  },
  pressed: {
    opacity: 0.6,
  },
  rowIcon: {
    width: 32,
    height: 32,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowIconDestructive: {
    backgroundColor: colors.errorSoft,
  },
  rowLabel: {
    ...typography.body,
    color: colors.textPrimary,
    flexShrink: 0,
  },
  rowValue: {
    ...typography.caption,
    color: colors.textSecondary,
    flex: 1,
    textAlign: 'right',
  },
  rowValueMuted: {
    fontStyle: 'italic',
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
  },
  editBlock: {
    paddingVertical: spacing.lg,
    gap: spacing.md,
  },
  editActions: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  editAction: {
    flex: 1,
  },
  languageOptions: {
    paddingLeft: 32 + spacing.md,
    paddingBottom: spacing.sm,
  },
  languageOption: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    minHeight: 44,
  },
  languageLabel: {
    ...typography.body,
    color: colors.textPrimary,
  },
  languageLabelSelected: {
    fontWeight: '600',
    color: colors.primary,
  },
  signOutLabel: {
    ...typography.body,
    fontWeight: '600',
    color: colors.errorDark,
  },
  version: {
    ...typography.caption,
    color: colors.textSecondary,
    textAlign: 'center',
  },
});

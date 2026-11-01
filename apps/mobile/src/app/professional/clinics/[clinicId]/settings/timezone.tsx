import { Ionicons } from '@expo/vector-icons';
import * as Localization from 'expo-localization';
import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AccessibilityInfo,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { ClinicSettingsEditorStateView } from '@/components/clinic-settings-editor-state-view';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Input } from '@/components/design-system/input';
import { Notice } from '@/components/design-system/notice';
import { PillButton } from '@/components/design-system/pill-button';
import { saveClinicSchedulingTimezone } from '@/data/clinic-settings';
import {
  useClinicSettingsEditor,
  type ClinicSettingsEditorRead,
} from '@/hooks/use-clinic-settings-editor';
import { mapClinicTimezoneSaveErrorToKey } from '@/i18n/clinic-settings-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { clinicSettingsHref } from '@/lib/clinic-settings';
import {
  TIMEZONE_RESULTS_LIMIT,
  canSaveTimezone,
  deviceTimezoneSuggestion,
  searchTimezones,
  timezoneLabel,
  timezoneSaveFailure,
  timezoneSelectionState,
} from '@/lib/clinic-timezone';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/** The device's timezone, read only to offer it as a suggestion. */
function deviceTimezone(): string | null {
  try {
    return Localization.getCalendars()[0]?.timeZone ?? null;
  } catch {
    return null;
  }
}

/**
 * Edits the Clinic's scheduling timezone (SPEC-APT-013 BR-76): the actor
 * explicitly chooses one named IANA timezone from a searchable list (or the
 * device's timezone, offered only as a suggestion); the canonical IANA name is
 * saved. Nothing is derived from the location, the address, or the device
 * position. It never clears the timezone. Changing it does not move existing
 * Appointments or change the location (BR-47–BR-50, BR-45).
 *
 * The backend is authoritative: an invalid name, or a change blocked by BR-56
 * (current Appointment Availability without PROFESSIONAL_SCHEDULING), is
 * shown as calm copy, keeping the selection. Save, re-read, lost-response,
 * access-loss, and terminal-leaving behaviour are those of the Profile editor;
 * timezone saves are last-write-wins (BR-75).
 *
 * A search result and the device suggestion select in exactly the same way:
 * an unsaved choice appears as a "selected timezone" block right under the
 * current value (check icon + text, not color alone) and is announced; it is
 * applied only by Save.
 */
export default function ClinicTimezoneEditorScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const {
    state,
    reload,
    leave: leaveScreen,
    isActive,
  } = useClinicSettingsEditor(clinicId, 'timezone');
  const [loaded, setLoaded] = useState(false);
  const [selected, setSelected] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [saving, setSaving] = useState(false);
  const [errorKey, setErrorKey] = useState<TranslationKey | null>(null);
  // Read once, on open; only ever a suggestion.
  const [suggestion] = useState(() => deviceTimezoneSuggestion(deviceTimezone()));

  const busyRef = useRef(false);

  const leave = useCallback(() => {
    leaveScreen(() => router.dismissTo(clinicSettingsHref(clinicId)));
  }, [leaveScreen, clinicId]);

  const initialize = useCallback(
    (read: ClinicSettingsEditorRead | null) => {
      if (read?.kind === 'loaded' && isActive()) setLoaded(true);
    },
    [isActive],
  );

  useEffect(() => {
    reload().then(initialize);
  }, [reload, initialize]);

  if (state.kind !== 'loaded' || !loaded) {
    return (
      <SafeAreaView style={styles.safeArea}>
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <AppTopBar onBack={leave} />
          <ClinicSettingsEditorStateView
            state={state.kind === 'loaded' ? { kind: 'loading' } : state}
            onRetry={() => reload().then(initialize)}
            onBack={leave}
          />
        </View>
      </SafeAreaView>
    );
  }

  const stored = state.profile.schedulingTimezoneName;
  const saveEnabled = canSaveTimezone({ selected, stored, busy: saving });
  const selection = timezoneSelectionState({ selected, stored, suggestion });
  const results = searchTimezones(query);
  const shown = results.slice(0, TIMEZONE_RESULTS_LIMIT);
  const describe = (name: string) => {
    const label = timezoneLabel(name);
    return label.region === '' ? label.name : `${label.city} · ${label.name}`;
  };

  const choose = (name: string) => {
    if (saving) return;
    setSelected(name);
    setErrorKey(null);
    if (name !== stored) {
      AccessibilityInfo.announceForAccessibility(
        t('clinicSettingsTimezone.selectedAnnouncement', { timezone: describe(name) }),
      );
    }
  };

  async function save() {
    if (busyRef.current || !isActive() || !saveEnabled || selected === null) return;
    const submitted = selected;
    busyRef.current = true;
    setSaving(true);
    setErrorKey(null);
    try {
      const result = await saveClinicSchedulingTimezone(clinicId, submitted);
      if (!isActive()) return;
      if (result.error === null) {
        leave();
        return;
      }
      const read = await reload();
      if (!isActive()) return;
      const outcome = timezoneSaveFailure(read, submitted);
      if (outcome === 'committed') {
        leave();
        return;
      }
      // The selection is kept; 'accessLost' already replaced the form.
      if (outcome === 'failed') setErrorKey(mapClinicTimezoneSaveErrorToKey(result.error));
    } finally {
      busyRef.current = false;
      if (isActive()) setSaving(false);
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
          <AppTopBar onBack={leave} />
          <Text style={styles.title} accessibilityRole="header">
            {t('clinicSettingsTimezone.title')}
          </Text>
          <Text style={styles.hint}>{t('clinicSettingsTimezone.intro')}</Text>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>{t('clinicSettingsTimezone.currentHeading')}</Text>
            <Text style={styles.value}>
              {stored === null ? t('clinicSettingsTimezone.currentMissing') : describe(stored)}
            </Text>
          </View>

          {selection.pending !== null ? (
            <View style={styles.selectedBlock} accessible>
              <View style={styles.selectedHeader}>
                <Ionicons
                  name="checkmark-circle"
                  size={20}
                  color={colors.primary}
                  accessibilityElementsHidden
                  importantForAccessibility="no-hide-descendants"
                />
                <Text style={styles.selectedHeading}>
                  {t('clinicSettingsTimezone.selectedHeading')}
                </Text>
              </View>
              <Text style={styles.selectedCity}>{selection.pending.city}</Text>
              <Text style={styles.value}>{selection.pending.name}</Text>
              <Text style={styles.hint}>{t('clinicSettingsTimezone.selectedUnsaved')}</Text>
            </View>
          ) : null}

          {suggestion !== null && selection.offerDeviceSuggestion ? (
            <View style={styles.actions}>
              <PillButton
                icon="phone-portrait-outline"
                label={t('clinicSettingsTimezone.useDeviceTimezone', {
                  timezone: describe(suggestion),
                })}
                onPress={() => choose(suggestion)}
              />
            </View>
          ) : null}

          <View style={styles.section}>
            <Input
              label={t('clinicSettingsTimezone.searchLabel')}
              value={query}
              onChangeText={setQuery}
              autoCapitalize="none"
              autoCorrect={false}
              editable={!saving}
              returnKeyType="search"
            />
            <Text style={styles.hint}>{t('clinicSettingsTimezone.searchHint')}</Text>
            {query.trim() !== '' && results.length === 0 ? (
              <Text style={styles.hint}>{t('clinicSettingsTimezone.noResults')}</Text>
            ) : null}
            {shown.length > 0 ? (
              <View style={styles.card} accessibilityRole="radiogroup">
                {shown.map((name) => {
                  const label = timezoneLabel(name);
                  const isSelected = name === selected;
                  return (
                    <Pressable
                      key={name}
                      onPress={() => choose(name)}
                      accessibilityRole="radio"
                      accessibilityState={{ selected: isSelected, checked: isSelected }}
                      accessibilityLabel={describe(name)}
                      style={({ pressed }) => [styles.option, pressed && styles.pressed]}
                    >
                      <View style={styles.optionText}>
                        <Text style={styles.optionCity}>{label.city}</Text>
                        <Text style={styles.hint}>{label.name}</Text>
                      </View>
                      {isSelected ? (
                        <Ionicons
                          name="checkmark-circle"
                          size={22}
                          color={colors.primary}
                          accessibilityElementsHidden
                          importantForAccessibility="no-hide-descendants"
                        />
                      ) : null}
                    </Pressable>
                  );
                })}
              </View>
            ) : null}
            {results.length > shown.length ? (
              <Text style={styles.hint}>{t('clinicSettingsTimezone.refineSearch')}</Text>
            ) : null}
          </View>

          <Text style={styles.hint}>{t('clinicSettingsTimezone.effectNote')}</Text>
        </ScrollView>

        <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
          {selected !== null && selection.pending !== null ? (
            <Text style={styles.hint}>
              {t('clinicSettingsTimezone.selected', { timezone: describe(selected) })}
            </Text>
          ) : null}
          {errorKey !== null ? <Notice tone="error" message={t(errorKey)} /> : null}
          <Button
            label={t('clinicSettings.save')}
            onPress={save}
            loading={saving}
            disabled={!saveEnabled}
          />
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
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
    paddingBottom: spacing.xl,
    gap: spacing.lg,
  },
  title: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  section: {
    gap: spacing.sm,
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  value: {
    ...typography.body,
    color: colors.textPrimary,
  },
  hint: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
  },
  selectedBlock: {
    gap: 2,
    borderWidth: 2,
    borderColor: colors.primary,
    backgroundColor: colors.primarySoft,
    borderRadius: radius.medium,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
  },
  selectedHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    marginBottom: spacing.xs,
  },
  selectedHeading: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primaryDark,
    flexShrink: 1,
  },
  selectedCity: {
    ...typography.h3,
    color: colors.textPrimary,
  },
  card: {
    borderRadius: radius.medium,
    backgroundColor: colors.surfaceSoft,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    minHeight: 44,
    paddingVertical: spacing.sm,
    borderRadius: radius.medium,
  },
  pressed: {
    backgroundColor: colors.primarySoft,
  },
  optionText: {
    flex: 1,
    gap: 2,
  },
  optionCity: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  footer: {
    gap: spacing.sm,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.md,
    backgroundColor: colors.background,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});

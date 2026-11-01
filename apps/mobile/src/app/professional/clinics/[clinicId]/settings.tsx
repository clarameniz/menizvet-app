import { Ionicons } from '@expo/vector-icons';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useRef, useState, type ComponentProps, type ReactNode } from 'react';
import {
  AccessibilityInfo,
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { PillButton } from '@/components/design-system/pill-button';
import { StateMessage } from '@/components/design-system/state-message';
import { publishClinic, unpublishClinic } from '@/data/clinic-settings';
import { useClinicSettings, type ClinicSettingsState } from '@/hooks/use-clinic-settings';
import { mapClinicPublicationErrorToKey } from '@/i18n/clinic-settings-error-messages';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { appointmentHoursHref } from '@/lib/appointment-hours';
import {
  clinicSettingsEditorHref,
  clinicSettingsOverview,
  clinicSettingsStatusSummary,
  isSettingsItemActionable,
  publicationAction,
  publicationSaveFailure,
  SETTINGS_ITEM_COPY,
  SETTINGS_STATUS_TONE,
  type ClinicSettingsInput,
  type OnlineAppointmentSetup,
  type PublicationRequirement,
  type SettingsItem,
  type SettingsItemKey,
  type SettingsItemStatus,
  type SettingsStatusTone,
} from '@/lib/clinic-settings';
import { goBackOr } from '@/lib/navigation';
import { organizationSubscriptionHref } from '@/lib/organization-subscription';
import { professionalClinicLabel } from '@/lib/professional-clinics-display';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type IconName = ComponentProps<typeof Ionicons>['name'];

const STATUS_PRESENTATION: Record<SettingsItemStatus, { key: TranslationKey; icon: IconName }> = {
  complete: { key: 'clinicSettings.statusComplete', icon: 'checkmark-circle' },
  missing: { key: 'clinicSettings.statusMissing', icon: 'alert-circle-outline' },
  needsAttention: { key: 'clinicSettings.statusNeedsAttention', icon: 'alert-circle-outline' },
  unknown: { key: 'clinicSettings.statusUnknown', icon: 'help-circle-outline' },
  published: { key: 'clinicSettings.statusPublished', icon: 'eye-outline' },
  notPublished: { key: 'clinicSettings.statusNotPublished', icon: 'eye-off-outline' },
};

const TONE_COLORS: Record<SettingsStatusTone, string> = {
  positive: colors.success,
  attention: colors.warning,
  neutral: colors.textMuted,
};

const ONLINE_SETUP_PRESENTATION: Record<
  OnlineAppointmentSetup,
  { stateKey: TranslationKey; noteKey: TranslationKey; icon: IconName; tone: SettingsStatusTone }
> = {
  complete: {
    stateKey: 'clinicSettings.onlineStateComplete',
    noteKey: 'clinicSettings.onlineComplete',
    icon: 'checkmark-circle',
    tone: 'positive',
  },
  incomplete: {
    stateKey: 'clinicSettings.onlineStateIncomplete',
    noteKey: 'clinicSettings.onlineIncomplete',
    icon: 'alert-circle-outline',
    tone: 'attention',
  },
  unknown: {
    stateKey: 'clinicSettings.onlineStateUnknown',
    noteKey: 'clinicSettings.onlineUnknown',
    icon: 'help-circle-outline',
    tone: 'neutral',
  },
};

/**
 * Clinic settings overview (SPEC-CLI-007 BR-7–BR-12). Two separate status
 * cards answer whether the public can find the Clinic and whether the known
 * setup for online Appointment requests is complete — never that times are
 * available — and the Setup list shows each item with its value and status
 * (icon + label, not color alone). The profile, location, and time zone rows
 * open their editors (each only with its own capability); the duration and
 * hours rows open the existing Appointment hours screens.
 *
 * Publication (SPEC-CLI-003 BR-15, BR-16, BR-21) is controlled in the
 * visibility card — the only place with Publish/Unpublish; the Visibility row
 * below is a read-only status. Publish
 * only once a display name and a location exist (otherwise what is missing is
 * listed — a time zone is not required), Unpublish once published, each after
 * a confirmation and only with CLINIC_MANAGE_PUBLICATION. After either, the
 * screen re-reads the authoritative state — never an optimistic one; a failed
 * call whose re-read already shows the requested state counts as done.
 *
 * Re-reads everything on every focus, so returning from an editor shows the
 * authoritative result of its save. The managed Clinic read is required; if
 * only the Appointment hours read (or the professional context) fails, the
 * dependent items show as unknown with a Retry. Only the first load shows
 * loading/error states. Back is terminal (owned by the hook's `leave`);
 * opening an editor is not, since this screen stays mounted beneath it.
 */
export default function ClinicSettingsScreen() {
  const { t } = useLocale();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const { state, reload, leave, isActive } = useClinicSettings(clinicId);
  const [publishing, setPublishing] = useState(false);
  const [publicationErrorKey, setPublicationErrorKey] = useState<TranslationKey | null>(null);
  // A publication change is in flight; a ref, so a second tap can't submit twice.
  const publicationBusyRef = useRef(false);

  async function changePublication(publish: boolean) {
    if (publicationBusyRef.current || !isActive()) return;
    publicationBusyRef.current = true;
    setPublishing(true);
    setPublicationErrorKey(null);
    try {
      const result = publish ? await publishClinic(clinicId) : await unpublishClinic(clinicId);
      if (!isActive()) return;
      // Always re-read: the overview shows only the authoritative state.
      const read = await reload();
      if (!isActive()) return;
      const outcome =
        result.error === null && read?.kind === 'loaded'
          ? 'committed'
          : publicationSaveFailure(read, publish);
      if (outcome === 'committed') {
        AccessibilityInfo.announceForAccessibility(
          t(
            publish
              ? 'clinicSettings.publishedAnnouncement'
              : 'clinicSettings.unpublishedAnnouncement',
          ),
        );
        return;
      }
      // 'accessLost': the re-read already replaced the overview.
      if (outcome === 'failed') {
        setPublicationErrorKey(
          result.error === null
            ? 'clinicSettings.loadError'
            : mapClinicPublicationErrorToKey(result.error),
        );
      }
    } finally {
      publicationBusyRef.current = false;
      if (isActive()) setPublishing(false);
    }
  }

  const confirmPublication = (publish: boolean) =>
    Alert.alert(
      t(publish ? 'clinicSettings.publishConfirmTitle' : 'clinicSettings.unpublishConfirmTitle'),
      t(
        publish ? 'clinicSettings.publishConfirmMessage' : 'clinicSettings.unpublishConfirmMessage',
      ),
      [
        { text: t('clinicSettings.confirmCancel'), style: 'cancel' },
        {
          text: t(publish ? 'clinicSettings.publishAction' : 'clinicSettings.unpublishAction'),
          onPress: () => {
            void changePublication(publish);
          },
        },
      ],
    );

  useFocusEffect(
    useCallback(() => {
      reload();
    }, [reload]),
  );

  // Terminal: a focus read still in flight never updates this screen afterwards.
  const goBack = () =>
    leave(() => goBackOr({ pathname: '/professional/clinics/[clinicId]', params: { clinicId } }));

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <AppTopBar onBack={goBack} />
        <Text style={styles.title} accessibilityRole="header">
          {t('clinicSettings.title')}
        </Text>
        {state.kind === 'loaded' ? (
          <Overview
            input={state}
            onRetry={() => reload()}
            publication={{
              busy: publishing,
              errorKey: publicationErrorKey,
              onPublish: () => confirmPublication(true),
              onUnpublish: () => confirmPublication(false),
            }}
          />
        ) : (
          <SettingsStateView state={state} onRetry={() => reload()} onBack={goBack} />
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function SettingsStateView({
  state,
  onRetry,
  onBack,
}: {
  state: Exclude<ClinicSettingsState, { kind: 'loaded' }>;
  onRetry: () => void;
  onBack: () => void;
}) {
  const { t } = useLocale();

  if (state.kind === 'loading') {
    return <StateMessage tone="loading" message={t('clinicSettings.loading')} />;
  }
  if (state.kind === 'error') {
    return (
      <View style={styles.block}>
        <StateMessage tone="error" message={t(state.messageKey)} />
        <Button label={t('professional.retry')} onPress={onRetry} />
        <Button variant="secondary" label={t('clinicSettings.backToClinic')} onPress={onBack} />
      </View>
    );
  }
  return (
    <View style={styles.block}>
      <StateMessage
        tone="empty"
        icon="settings-outline"
        message={t('clinicSettings.unavailable')}
      />
      <Button variant="secondary" label={t('clinicSettings.backToClinic')} onPress={onBack} />
    </View>
  );
}

type PublicationControls = {
  busy: boolean;
  errorKey: TranslationKey | null;
  onPublish: () => void;
  onUnpublish: () => void;
};

const REQUIREMENT_KEYS: Record<PublicationRequirement, TranslationKey> = {
  profile: 'clinicSettings.requirementName',
  location: 'clinicSettings.requirementLocation',
};

function Overview({
  input,
  onRetry,
  publication,
}: {
  input: ClinicSettingsInput;
  onRetry: () => void;
  publication: PublicationControls;
}) {
  const { t } = useLocale();
  const overview = clinicSettingsOverview(input);
  const summary = clinicSettingsStatusSummary(overview);
  const online = ONLINE_SETUP_PRESENTATION[summary.onlineAppointments];
  const action = publicationAction(input);
  const { clinic, profile } = input;
  const partial = overview.schedulingUnknown || input.appointmentManagement === null;

  const details: Partial<Record<SettingsItemKey, string>> = {
    profile: profile.publicProfile?.displayName ?? undefined,
    location: profile.location?.addressText,
    timezone: profile.schedulingTimezoneName ?? undefined,
    duration:
      input.scheduling.kind === 'known' &&
      input.scheduling.hours.standardAppointmentDurationMinutes !== null
        ? t('clinicSettings.durationValue', {
            minutes: input.scheduling.hours.standardAppointmentDurationMinutes,
          })
        : undefined,
  };

  const open = (item: SettingsItem) => {
    if (item.target === 'profileEditor') {
      router.push(clinicSettingsEditorHref(clinic.clinicId, 'profile'));
    }
    if (item.target === 'locationEditor') {
      router.push(clinicSettingsEditorHref(clinic.clinicId, 'location'));
    }
    if (item.target === 'timezoneEditor') {
      router.push(clinicSettingsEditorHref(clinic.clinicId, 'timezone'));
    }
    if (item.target === 'appointmentHours') router.push(appointmentHoursHref(clinic.clinicId));
    if (item.target === 'durationEditor') {
      router.push({
        pathname: '/professional/clinics/[clinicId]/appointment-hours/duration',
        params: { clinicId: clinic.clinicId },
      });
    }
  };

  return (
    <>
      <Text style={styles.clinicName}>
        {professionalClinicLabel(clinic, t('professional.unnamedClinic'))}
      </Text>

      {partial ? (
        <View style={styles.block}>
          <Notice tone="info" message={t('clinicSettings.partialNotice')} />
          <Button variant="secondary" label={t('professional.retry')} onPress={onRetry} />
        </View>
      ) : null}

      <View style={styles.section}>
        <Text style={styles.sectionTitle} accessibilityRole="header">
          {t('clinicSettings.statusHeading')}
        </Text>

        <StatusCard
          icon={STATUS_PRESENTATION[summary.visibility].icon}
          tone={SETTINGS_STATUS_TONE[summary.visibility]}
          title={t('clinicSettings.itemPublication')}
          state={t(STATUS_PRESENTATION[summary.visibility].key)}
          note={t(
            summary.visibility === 'published'
              ? 'clinicSettings.findableYes'
              : 'clinicSettings.findableNo',
          )}
        >
          {action.kind === 'publish' ? (
            <>
              <Text style={styles.caption}>{t('clinicSettings.readyToPublish')}</Text>
              <Button
                label={t('clinicSettings.publishAction')}
                onPress={publication.onPublish}
                loading={publication.busy}
              />
            </>
          ) : null}
          {action.kind === 'publishBlocked' ? (
            <Text style={styles.caption}>
              {t('clinicSettings.publishMissing', {
                items: action.missing
                  .map((requirement) => t(REQUIREMENT_KEYS[requirement]))
                  .join(', '),
              })}
            </Text>
          ) : null}
          {action.kind === 'unpublish' ? (
            <>
              <Text style={styles.caption}>{t('clinicSettings.unpublishHint')}</Text>
              <Button
                variant="secondary"
                label={t('clinicSettings.unpublishAction')}
                onPress={publication.onUnpublish}
                loading={publication.busy}
              />
            </>
          ) : null}
          {action.kind === 'none' ? (
            <Text style={styles.caption}>
              {t(
                overview.published
                  ? 'clinicSettings.publicationReadOnly'
                  : overview.readyToPublish
                    ? 'clinicSettings.readyToPublishAskAdministrator'
                    : 'clinicSettings.notReadyToPublish',
              )}
            </Text>
          ) : null}
          {publication.errorKey !== null ? (
            <Notice tone="error" message={t(publication.errorKey)} />
          ) : null}
        </StatusCard>

        <StatusCard
          icon={online.icon}
          tone={online.tone}
          title={t('clinicSettings.onlineHeading')}
          state={t(online.stateKey)}
          note={t(online.noteKey)}
        >
          {summary.planNotice ? (
            <Notice tone="info" message={t('clinicSettings.planNotice')} />
          ) : null}
          {summary.planNotice && input.subscriptionStatusAccess ? (
            <PillButton
              icon="receipt-outline"
              label={t('clinicSettings.viewSubscription')}
              onPress={() => router.push(organizationSubscriptionHref(clinic.organizationId))}
            />
          ) : null}
        </StatusCard>
      </View>

      <View style={styles.section}>
        <Text style={styles.sectionTitle} accessibilityRole="header">
          {t('clinicSettings.itemsHeading')}
        </Text>
        <View style={styles.card}>
          {overview.items.map((item, index) => (
            <SettingsRow
              key={item.key}
              item={item}
              detail={details[item.key]}
              first={index === 0}
              onOpen={isSettingsItemActionable(item) ? () => open(item) : null}
            />
          ))}
        </View>
      </View>
    </>
  );
}

/**
 * One status card: an icon, the card's title, its state in strong text, a
 * one-line explanation, then any controls. The state is announced as text;
 * the tone color is on the icon only.
 */
function StatusCard({
  icon,
  tone,
  title,
  state,
  note,
  children,
}: {
  icon: IconName;
  tone: SettingsStatusTone;
  title: string;
  state: string;
  note: string;
  children?: ReactNode;
}) {
  return (
    <View style={styles.statusCard}>
      <View
        style={styles.statusCardHeader}
        accessible
        accessibilityLabel={`${title}: ${state}. ${note}`}
      >
        <View
          style={styles.statusBadge}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          <Ionicons name={icon} size={20} color={TONE_COLORS[tone]} />
        </View>
        <View style={styles.statusCardText}>
          <Text style={styles.caption}>{title}</Text>
          <Text style={styles.statusCardState} accessibilityLiveRegion="polite">
            {state}
          </Text>
          <Text style={styles.caption}>{note}</Text>
        </View>
      </View>
      {children}
    </View>
  );
}

/**
 * One Setup row, always in the same order — title, supporting text, current
 * value, status (icon + label) — with the chevron column on the right. A
 * read-only row keeps that column empty (so text aligns across rows) and is
 * not a button.
 */
function SettingsRow({
  item,
  detail,
  first,
  onOpen,
}: {
  item: SettingsItem;
  detail: string | undefined;
  first: boolean;
  onOpen: (() => void) | null;
}) {
  const { t } = useLocale();
  const copy = SETTINGS_ITEM_COPY[item.key];
  const label = t(copy.labelKey);
  const support = copy.supportKey === null ? null : t(copy.supportKey);
  const status = STATUS_PRESENTATION[item.status];
  const statusLabel = t(status.key);
  const guidance = item.askAdministrator ? t('clinicSettings.askAdministrator') : null;
  const summary = [label, support, detail, statusLabel, guidance].filter(Boolean).join(', ');

  const content = (
    <>
      <View style={styles.rowText}>
        <Text style={styles.rowLabel}>{label}</Text>
        {support !== null ? <Text style={styles.caption}>{support}</Text> : null}
        {detail !== undefined ? <Text style={styles.rowDetail}>{detail}</Text> : null}
        <View style={styles.status}>
          <Ionicons
            name={status.icon}
            size={16}
            color={TONE_COLORS[SETTINGS_STATUS_TONE[item.status]]}
            accessibilityElementsHidden
            importantForAccessibility="no-hide-descendants"
          />
          <Text style={styles.statusLabel}>{statusLabel}</Text>
        </View>
        {guidance !== null ? <Text style={styles.caption}>{guidance}</Text> : null}
      </View>
      <View
        style={styles.chevron}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        {onOpen !== null ? (
          <Ionicons name="chevron-forward" size={20} color={colors.textMuted} />
        ) : null}
      </View>
    </>
  );

  const rowStyle = [styles.row, !first && styles.rowDivider];

  return onOpen !== null ? (
    <Pressable
      onPress={onOpen}
      accessibilityRole="button"
      accessibilityLabel={summary}
      accessibilityHint={t('clinicSettings.openItemAccessibility', { item: label })}
      style={({ pressed }) => [...rowStyle, pressed && styles.pressed]}
    >
      {content}
    </Pressable>
  ) : (
    <View style={rowStyle} accessible accessibilityLabel={summary}>
      {content}
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  clinicName: {
    ...typography.h3,
    color: colors.textPrimary,
  },
  block: {
    gap: spacing.md,
  },
  section: {
    gap: spacing.md,
  },
  sectionTitle: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  statusCard: {
    gap: spacing.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    padding: spacing.lg,
  },
  statusCardHeader: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
  },
  statusBadge: {
    width: 36,
    height: 36,
    borderRadius: radius.pill,
    backgroundColor: colors.surfaceSoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statusCardText: {
    flex: 1,
    gap: 2,
  },
  statusCardState: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  caption: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  card: {
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: spacing.lg,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.md,
    minHeight: 44,
  },
  rowDivider: {
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
  chevron: {
    width: 20,
    alignItems: 'center',
  },
  pressed: {
    backgroundColor: colors.primarySoft,
  },
  rowText: {
    flex: 1,
    gap: 2,
  },
  rowLabel: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  rowDetail: {
    ...typography.body,
    color: colors.textPrimary,
  },
  status: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  statusLabel: {
    ...typography.caption,
    color: colors.textPrimary,
  },
});

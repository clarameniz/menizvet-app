import { Ionicons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect, useState, type ComponentProps, type ReactNode } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';

import { Button } from '@/components/design-system/button';
import { PublicTopBar } from '@/components/design-system/public-top-bar';
import { StateMessage } from '@/components/design-system/state-message';
import { getPublishedClinicDetail, type ClinicDetail } from '@/data/clinics';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { serviceCategoryLabelKey } from '@/lib/clinic-service-display';
import { goBackOr } from '@/lib/navigation';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type LoadState = 'loading' | 'error' | 'notFound' | 'loaded';

const WEEKDAY_KEYS: TranslationKey[] = [
  'discoveryDetail.weekdayMonday',
  'discoveryDetail.weekdayTuesday',
  'discoveryDetail.weekdayWednesday',
  'discoveryDetail.weekdayThursday',
  'discoveryDetail.weekdayFriday',
  'discoveryDetail.weekdaySaturday',
  'discoveryDetail.weekdaySunday',
];

/**
 * Public Clinic detail (SPEC-DIS-001/002/003): composed entirely from
 * approved public reads (see data/clinics.ts's getPublishedClinicDetail).
 * Zero rows from published_clinic_public_profiles — a nonexistent Clinic id
 * and an unpublished one, identically — produce the single generic
 * "not found" state below; nothing here distinguishes the two. No
 * protected Clinic/Organization/professional data or Appointment
 * availability is read or shown.
 *
 * "Request appointment" is offered to every viewer, exactly as before; the
 * Guardian/session gate lives in request-appointment.tsx itself.
 */
export default function ClinicDetailScreen() {
  const { t } = useLocale();
  const insets = useSafeAreaInsets();
  const { id } = useLocalSearchParams<{ id: string }>();

  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [detail, setDetail] = useState<ClinicDetail | null>(null);

  useEffect(() => {
    let isMounted = true;

    getPublishedClinicDetail(id).then((result) => {
      if (!isMounted) return;

      if (result.error !== null) {
        setLoadState('error');
        return;
      }

      if (!result.data) {
        setLoadState('notFound');
        return;
      }

      setDetail(result.data);
      setLoadState('loaded');
    });

    return () => {
      isMounted = false;
    };
  }, [id]);

  if (loadState === 'loading' || loadState === 'error' || loadState === 'notFound') {
    return (
      <SafeAreaView style={styles.safeArea}>
        {/* Always-light background: explicit dark status-bar icons, same as
            the auth screens. */}
        <StatusBar style="dark" />
        <View style={styles.stateContent}>
          <PublicTopBar fallbackHref="/clinics" />
          {loadState === 'loading' ? (
            <StateMessage tone="loading" message={t('discoveryDetail.loading')} />
          ) : (
            <>
              <StateMessage
                tone="error"
                message={
                  loadState === 'notFound'
                    ? t('discoveryDetail.notFound')
                    : t('discoveryDetail.loadError')
                }
              />
              {/* Back to the list beneath — with its search and pages — never
                  a second list; the list itself only when there is none. */}
              <Button
                variant="secondary"
                label={t('discoveryDetail.backToList')}
                onPress={() => goBackOr('/clinics')}
              />
            </>
          )}
        </View>
      </SafeAreaView>
    );
  }

  if (!detail) return null;

  const name = detail.profile.displayName ?? t('discoveryList.unnamedClinic');
  const { publicPhone, publicEmail, website } = detail.profile;
  const hasContact = Boolean(publicPhone || publicEmail || website);
  const recurringPeriods = detail.openingHours?.recurringPeriods ?? [];

  return (
    <SafeAreaView style={styles.safeArea} edges={['top', 'left', 'right']}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <PublicTopBar fallbackHref="/clinics" />

        <View style={styles.identity}>
          <Text style={styles.name} accessibilityRole="header">
            {name}
          </Text>
          {detail.profile.description ? (
            <Text style={styles.description}>{detail.profile.description}</Text>
          ) : null}
        </View>

        <View style={styles.infoCard}>
          <InfoSection icon="location-outline" title={t('discoveryDetail.locationTitle')}>
            {detail.location ? (
              <Text style={styles.bodyText}>{detail.location.addressText}</Text>
            ) : (
              <EmptyNote message={t('discoveryDetail.noLocation')} />
            )}
          </InfoSection>

          <Divider />

          <InfoSection icon="medkit-outline" title={t('discoveryDetail.servicesTitle')}>
            {detail.serviceOfferings.length === 0 ? (
              <EmptyNote message={t('discoveryDetail.noServices')} />
            ) : (
              detail.serviceOfferings.map((offering) => (
                <View key={offering.serviceCategory} style={styles.serviceItem}>
                  <Text style={styles.bodyStrongText}>
                    {t(serviceCategoryLabelKey(offering.serviceCategory))}
                  </Text>
                  {offering.publicDescription ? (
                    <Text style={styles.captionText}>{offering.publicDescription}</Text>
                  ) : null}
                </View>
              ))
            )}
          </InfoSection>

          <Divider />

          <InfoSection icon="time-outline" title={t('discoveryDetail.hoursTitle')}>
            {recurringPeriods.length === 0 ? (
              <EmptyNote message={t('discoveryDetail.noHours')} />
            ) : (
              recurringPeriods.map((period, index) => {
                const weekdayKey = WEEKDAY_KEYS[period.isoWeekday - 1];
                const weekday = weekdayKey ? t(weekdayKey) : String(period.isoWeekday);
                const range = `${period.startTime}–${period.endTime}`;
                return (
                  <View
                    key={`${period.isoWeekday}-${period.startTime}-${index}`}
                    style={styles.hoursRow}
                    accessible
                    accessibilityLabel={`${weekday}: ${range}`}
                  >
                    <Text style={styles.bodyText}>{weekday}</Text>
                    <Text style={styles.bodyStrongText}>{range}</Text>
                  </View>
                );
              })
            )}
          </InfoSection>

          {hasContact ? (
            <>
              <Divider />
              <InfoSection icon="call-outline" title={t('discoveryDetail.contactTitle')}>
                {publicPhone ? (
                  <ContactRow label={t('discoveryDetail.phoneLabel')} value={publicPhone} />
                ) : null}
                {publicEmail ? (
                  <ContactRow label={t('discoveryDetail.emailLabel')} value={publicEmail} />
                ) : null}
                {website ? (
                  <ContactRow label={t('discoveryDetail.websiteLabel')} value={website} />
                ) : null}
              </InfoSection>
            </>
          ) : null}
        </View>
      </ScrollView>

      {/* Pinned CTA: same action and route as before, always reachable
          without scrolling past every section. */}
      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md }]}>
        <Button
          label={t('appointmentRequest.title')}
          onPress={() => router.push(`/clinics/${id}/request-appointment`)}
        />
      </View>
    </SafeAreaView>
  );
}

type InfoSectionProps = {
  icon: ComponentProps<typeof Ionicons>['name'];
  title: string;
  children: ReactNode;
};

function InfoSection({ icon, title, children }: InfoSectionProps) {
  return (
    <View style={styles.section}>
      <View style={styles.sectionHeader}>
        <View
          style={styles.sectionIcon}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        >
          <Ionicons name={icon} size={16} color={colors.primary} />
        </View>
        <Text style={styles.sectionTitle} accessibilityRole="header">
          {title}
        </Text>
      </View>
      <View style={styles.sectionBody}>{children}</View>
    </View>
  );
}

function EmptyNote({ message }: { message: string }) {
  return <Text style={styles.emptyNote}>{message}</Text>;
}

function ContactRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.contactRow} accessible accessibilityLabel={`${label}: ${value}`}>
      <Text style={styles.captionText}>{label}</Text>
      <Text style={styles.bodyText}>{value}</Text>
    </View>
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
    gap: spacing.xl,
  },
  identity: {
    gap: spacing.sm,
  },
  // h2, not h1/display: long Clinic names wrap to at most a couple of lines
  // instead of taking over the viewport.
  name: {
    ...typography.h2,
    color: colors.textPrimary,
  },
  description: {
    ...typography.body,
    color: colors.textSecondary,
  },
  infoCard: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    paddingHorizontal: spacing.lg,
  },
  section: {
    paddingVertical: spacing.lg,
    gap: spacing.sm,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
  },
  sectionIcon: {
    width: 28,
    height: 28,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  // Aligned with the section title's text, not the icon badge.
  sectionBody: {
    paddingLeft: 28 + spacing.sm,
    gap: spacing.sm,
  },
  bodyText: {
    ...typography.body,
    color: colors.textPrimary,
  },
  bodyStrongText: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  captionText: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  emptyNote: {
    ...typography.caption,
    color: colors.textSecondary,
    fontStyle: 'italic',
  },
  serviceItem: {
    gap: 2,
  },
  hoursRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: spacing.md,
  },
  contactRow: {
    gap: 2,
  },
  divider: {
    height: StyleSheet.hairlineWidth,
    backgroundColor: colors.border,
  },
  footer: {
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.md,
    backgroundColor: colors.background,
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: colors.border,
  },
});

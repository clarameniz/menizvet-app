import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppointmentHoursStateView } from '@/components/appointment-hours-state-view';
import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { Notice } from '@/components/design-system/notice';
import { PillButton } from '@/components/design-system/pill-button';
import type { ClinicAppointmentHours } from '@/data/clinic-appointment-hours';
import { useAppointmentHours } from '@/hooks/use-appointment-hours';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  ISO_WEEKDAYS,
  accessNoticeKey,
  canEditAvailability,
  canEditDuration,
  exceptionPresentation,
  formatExceptionDate,
  formatTimeRanges,
  recurringRangesFor,
  upcomingExceptions,
  type AppointmentHoursAccess,
  type ExceptionPresentation,
} from '@/lib/appointment-hours';
import { clinicLocalToday } from '@/lib/appointment-time';
import { goBackOr } from '@/lib/navigation';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

const PRESENTATION_KEYS: Record<ExceptionPresentation, TranslationKey> = {
  closedAllDay: 'appointmentHours.exceptionClosedAllDay',
  openExceptionally: 'appointmentHours.exceptionOpenExceptionally',
  customHours: 'appointmentHours.exceptionCustomHours',
};

/**
 * Appointment hours of one Professional Clinic (SPEC-APT-013 BR-57–BR-62,
 * BR-72–BR-75): the standard Appointment duration, the recurring weekly
 * Appointment availability, and upcoming one-day exceptions, each with an
 * Edit entry when editable. "Appointment hours" is Appointment availability —
 * never the Clinic's public Opening Hours.
 *
 * Re-reads everything on every focus (so returning from an editor shows the
 * authoritative result of the save). Offered only with the advisory
 * APPOINTMENT_MANAGE_AVAILABILITY capability; read-only while the
 * Organization lacks PROFESSIONAL_SCHEDULING, or — with a Retry — while the
 * professional context can't be read to confirm it; weekly hours and exceptions are
 * not editable while the Clinic has no scheduling timezone, which is shown
 * read-only and never edited here. Past exceptions are hidden by Clinic-local
 * date. Only the first load shows loading/error states. Back is terminal
 * (owned by the hook's `leave`); opening an editor is not, since this screen
 * stays mounted beneath it and re-reads when it regains focus.
 */
export default function AppointmentHoursScreen() {
  const { t } = useLocale();
  const { clinicId } = useLocalSearchParams<{ clinicId: string }>();
  const { state, reload, leave } = useAppointmentHours(clinicId);

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
          {t('appointmentHours.title')}
        </Text>
        {state.kind === 'loaded' ? (
          <Configuration
            config={state.config}
            access={state.access}
            clinicId={clinicId}
            onRetry={() => reload()}
          />
        ) : (
          <AppointmentHoursStateView
            state={state}
            onRetry={() => reload()}
            onBack={goBack}
            backLabel={t('appointmentHours.backToClinic')}
          />
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

function Configuration({
  config,
  access,
  clinicId,
  onRetry,
}: {
  config: ClinicAppointmentHours;
  access: AppointmentHoursAccess;
  clinicId: string;
  onRetry: () => void;
}) {
  const { t, locale } = useLocale();
  const timezone = config.schedulingTimezoneName;
  const accessNotice = accessNoticeKey(access);
  const availabilityEditable = canEditAvailability(config, access);
  const exceptions = upcomingExceptions(
    config.exceptions,
    timezone === null ? null : clinicLocalToday(timezone),
  );

  const openEditor = (editor: 'duration' | 'weekly') =>
    router.push(
      editor === 'duration'
        ? {
            pathname: '/professional/clinics/[clinicId]/appointment-hours/duration',
            params: { clinicId },
          }
        : {
            pathname: '/professional/clinics/[clinicId]/appointment-hours/weekly',
            params: { clinicId },
          },
    );
  const openException = (date?: string) =>
    router.push({
      pathname: '/professional/clinics/[clinicId]/appointment-hours/exception',
      params: date === undefined ? { clinicId } : { clinicId, date },
    });

  return (
    <>
      {timezone !== null ? (
        <Text style={styles.caption}>{t('appointmentHours.timezoneCaption', { timezone })}</Text>
      ) : (
        <Notice tone="info" message={t('appointmentHours.timezoneMissingNotice')} />
      )}
      {accessNotice !== null ? <Notice tone="info" message={t(accessNotice)} /> : null}
      {access === 'unconfirmed' ? (
        <Button variant="secondary" label={t('professional.retry')} onPress={onRetry} />
      ) : null}

      <View style={styles.section}>
        <SectionHeader
          title={t('appointmentHours.durationHeading')}
          editAccessibilityLabel={t('appointmentHours.editDurationAccessibility')}
          onEdit={canEditDuration(access) ? () => openEditor('duration') : null}
        />
        {config.standardAppointmentDurationMinutes !== null ? (
          <Text style={styles.value}>
            {t('appointmentHours.durationValue', {
              minutes: config.standardAppointmentDurationMinutes,
            })}
          </Text>
        ) : (
          <>
            <Text style={styles.value}>{t('appointmentHours.durationNotSet')}</Text>
            <Text style={styles.caption}>{t('appointmentHours.durationNotSetHint')}</Text>
          </>
        )}
      </View>

      <View style={styles.section}>
        <SectionHeader
          title={t('appointmentHours.weeklyHeading')}
          editAccessibilityLabel={t('appointmentHours.editWeeklyAccessibility')}
          onEdit={availabilityEditable ? () => openEditor('weekly') : null}
        />
        <View style={styles.card}>
          {ISO_WEEKDAYS.map((weekday) => {
            const ranges = recurringRangesFor(config.recurringPeriods, weekday);
            const hours =
              ranges.length === 0 ? t('appointmentHours.closed') : formatTimeRanges(ranges);
            return (
              <View
                key={weekday}
                style={styles.weekRow}
                accessible
                accessibilityLabel={`${t(`appointmentHours.weekday${weekday}`)}: ${hours}`}
              >
                <Text style={styles.weekday}>{t(`appointmentHours.weekdayShort${weekday}`)}</Text>
                <Text style={[styles.hours, ranges.length === 0 && styles.closed]}>{hours}</Text>
              </View>
            );
          })}
        </View>
      </View>

      <View style={styles.section}>
        <SectionHeader title={t('appointmentHours.exceptionsHeading')} onEdit={null} />
        {exceptions.length === 0 ? (
          <Text style={styles.caption}>{t('appointmentHours.noExceptions')}</Text>
        ) : (
          <View style={styles.card}>
            {exceptions.map((exception) => {
              const date = formatExceptionDate(exception.localDate, locale);
              const kind = t(
                PRESENTATION_KEYS[exceptionPresentation(exception, config.recurringPeriods)],
              );
              const hours = exception.kind === 'OPEN' ? formatTimeRanges(exception.periods) : null;
              const summary = hours === null ? `${date}: ${kind}` : `${date}: ${kind}, ${hours}`;
              const content = (
                <>
                  <Text style={styles.exceptionDate}>{date}</Text>
                  <Text style={styles.hours}>{hours === null ? kind : `${kind} · ${hours}`}</Text>
                </>
              );
              return availabilityEditable ? (
                <Pressable
                  key={exception.localDate}
                  onPress={() => openException(exception.localDate)}
                  accessibilityRole="button"
                  accessibilityLabel={summary}
                  accessibilityHint={t('appointmentHours.editExceptionAccessibility', { date })}
                  style={({ pressed }) => [styles.exceptionRow, pressed && styles.pressed]}
                >
                  {content}
                </Pressable>
              ) : (
                <View
                  key={exception.localDate}
                  style={styles.exceptionRow}
                  accessible
                  accessibilityLabel={summary}
                >
                  {content}
                </View>
              );
            })}
          </View>
        )}
        {availabilityEditable ? (
          <View style={styles.addRow}>
            <PillButton
              icon="add"
              label={t('appointmentHours.addException')}
              onPress={() => openException()}
            />
          </View>
        ) : null}
      </View>

      <Text style={styles.caption}>{t('appointmentHours.existingAppointmentsNote')}</Text>
    </>
  );
}

function SectionHeader({
  title,
  onEdit,
  editAccessibilityLabel,
}: {
  title: string;
  onEdit: (() => void) | null;
  editAccessibilityLabel?: string;
}) {
  const { t } = useLocale();
  return (
    <View style={styles.sectionHeader}>
      <Text style={styles.sectionTitle} accessibilityRole="header">
        {title}
      </Text>
      {onEdit !== null ? (
        <Pressable
          onPress={onEdit}
          accessibilityRole="button"
          accessibilityLabel={editAccessibilityLabel ?? t('appointmentHours.edit')}
          hitSlop={8}
          style={({ pressed }) => [styles.editButton, pressed && styles.pressed]}
        >
          <Text style={styles.editLabel}>{t('appointmentHours.edit')}</Text>
        </Pressable>
      ) : null}
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
  caption: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  section: {
    gap: spacing.sm,
  },
  sectionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.md,
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    flexShrink: 1,
  },
  editButton: {
    minHeight: 44,
    minWidth: 44,
    paddingHorizontal: spacing.sm,
    justifyContent: 'center',
    alignItems: 'center',
    borderRadius: radius.medium,
  },
  editLabel: {
    ...typography.bodyStrong,
    color: colors.primary,
  },
  pressed: {
    backgroundColor: colors.primarySoft,
  },
  value: {
    ...typography.body,
    color: colors.textPrimary,
  },
  card: {
    borderRadius: radius.medium,
    backgroundColor: colors.surfaceSoft,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.xs,
  },
  weekRow: {
    flexDirection: 'row',
    gap: spacing.md,
    paddingVertical: spacing.sm,
  },
  weekday: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    width: 48,
  },
  hours: {
    ...typography.body,
    color: colors.textPrimary,
    flexShrink: 1,
  },
  closed: {
    color: colors.textSecondary,
  },
  exceptionRow: {
    gap: 2,
    paddingVertical: spacing.sm,
    minHeight: 44,
    borderRadius: radius.medium,
  },
  exceptionDate: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  addRow: {
    alignItems: 'flex-start',
  },
});

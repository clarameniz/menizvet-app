import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { AppointmentStatusBadge } from '@/components/design-system/appointment-status-badge';
import type { ClinicScheduleAppointment } from '@/data/clinic-appointment-schedule';
import { useLocale } from '@/i18n/locale-provider';
import { lifecycleLabelKey } from '@/lib/appointment-lifecycle';
import { requesterLine } from '@/lib/appointment-requester-contact';
import { formatScheduledInterval } from '@/lib/appointment-time';
import {
  appointmentLocalDate,
  compactAppointmentDate,
  compactAppointmentTimes,
  formatDayHeading,
  showsAppointmentTimezone,
} from '@/lib/clinic-calendar';
import { showsPendingReschedule } from '@/lib/clinic-schedule-display';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/** A discreet labelled tag on a row: an icon AND text, never color alone. */
export type ClinicAppointmentRowTag = {
  icon: ComponentProps<typeof Ionicons>['name'];
  iconColor: string;
  text: string;
};

/** A list row's secondary line (Pending's reason): short visible text, full accessible text. */
export type ClinicAppointmentRowNote = ClinicAppointmentRowTag & { accessibilityText: string };

/**
 * One Appointment row of the professional agenda (SPEC-APT-012 §14): Pet,
 * requester (BR-49: current display name or the neutral fallback — never an
 * email), the real lifecycle state as the shared status badge (icon and text,
 * never color alone), and a discreet note for an interval established in
 * another timezone than the Clinic's current one (BR-60).
 *
 * - `day` (the calendar's selected day): start and end times, the reason for
 *   visit, and a note for a pending reschedule (BR-44).
 * - `list` (Pending and History, which span many dates): the start time over
 *   a short date ("15 oct", with the year only outside the current one), plus
 *   an optional `note` line — Pending's reason (BR-57), shown short and
 *   announced in full. The accessible name carries the full date.
 *
 * Times and dates are shown in the timezone the interval was established in.
 * The whole row is ONE button that opens the Appointment detail, where every
 * action lives; it holds no other control. Visible text may be truncated, but
 * the accessible name always carries the full details.
 */
export function ClinicCalendarAppointmentRow({
  appointment,
  clinicTimezoneName,
  onOpen,
  layout = 'day',
  note = null,
}: {
  appointment: ClinicScheduleAppointment;
  /** The Clinic's CURRENT valid timezone (BR-60), or `null` when it has none. */
  clinicTimezoneName: string | null;
  onOpen: () => void;
  layout?: 'day' | 'list';
  note?: ClinicAppointmentRowNote | null;
}) {
  const { t, locale } = useLocale();
  const times = compactAppointmentTimes(appointment, locale);
  const interval = formatScheduledInterval(
    appointment.currentScheduledStartAt,
    appointment.currentScheduledEndAt,
    appointment.currentSchedulingTimezoneName,
    locale,
  );
  const isDay = layout === 'day';
  const requester = requesterLine(appointment.requesterDisplayName, t);
  const lifecycleLabel = t(lifecycleLabelKey(appointment.lifecycleState));
  const pendingLabel =
    isDay && showsPendingReschedule(appointment) ? t('clinicSchedule.pendingReschedule') : null;
  const timezoneLabel = showsAppointmentTimezone(appointment, clinicTimezoneName)
    ? t('clinicCalendar.timezoneNote', { zone: appointment.currentSchedulingTimezoneName })
    : null;

  return (
    <Pressable
      onPress={onOpen}
      accessibilityRole="button"
      accessibilityLabel={[
        isDay ? null : formatDayHeading(appointmentLocalDate(appointment), locale),
        interval.time,
        appointment.petName,
        requester,
        lifecycleLabel,
        note?.accessibilityText,
        isDay ? appointment.reasonForVisit : null,
        pendingLabel,
        timezoneLabel,
      ]
        .filter(Boolean)
        .join(', ')}
      accessibilityHint={t('clinicSchedule.openDetailHint')}
      style={({ pressed }) => [styles.row, pressed && styles.pressed]}
    >
      <View style={[styles.timeColumn, !isDay && styles.dateColumn]}>
        <Text style={styles.startTime}>{times.start}</Text>
        <Text style={styles.endTime} numberOfLines={1}>
          {!isDay
            ? compactAppointmentDate(appointment, locale)
            : times.endsLater
              ? t('clinicCalendar.endsNextDay', { time: times.end })
              : times.end}
        </Text>
      </View>

      <View style={styles.content}>
        <Text style={styles.petName} numberOfLines={1}>
          {appointment.petName}
        </Text>
        <Text style={styles.detail} numberOfLines={1}>
          {requester}
        </Text>
        {isDay ? (
          <Text style={styles.detail} numberOfLines={1}>
            {appointment.reasonForVisit}
          </Text>
        ) : null}
        {note !== null ? (
          <View style={styles.note}>
            <Ionicons
              name={note.icon}
              size={14}
              color={note.iconColor}
              accessibilityElementsHidden
              importantForAccessibility="no-hide-descendants"
            />
            <Text style={styles.noteText} numberOfLines={1}>
              {note.text}
            </Text>
          </View>
        ) : null}
        <View style={styles.tags}>
          <AppointmentStatusBadge state={appointment.lifecycleState} />
          {pendingLabel !== null ? (
            <Tag icon="swap-horizontal-outline" iconColor={colors.warning} text={pendingLabel} />
          ) : null}
          {timezoneLabel !== null ? (
            <Tag icon="globe-outline" iconColor={colors.textSecondary} text={timezoneLabel} />
          ) : null}
        </View>
      </View>

      <Ionicons
        name="chevron-forward"
        size={18}
        color={colors.textMuted}
        style={styles.chevron}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
    </Pressable>
  );
}

function Tag({ icon, iconColor, text }: ClinicAppointmentRowTag) {
  return (
    <View style={styles.tag}>
      <Ionicons
        name={icon}
        size={13}
        color={iconColor}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <Text style={styles.tagText} numberOfLines={1}>
        {text}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
    backgroundColor: colors.surface,
  },
  pressed: {
    backgroundColor: colors.surfaceSoft,
  },
  timeColumn: {
    width: 64,
    paddingTop: 2,
  },
  // Sized by its content ("15 oct 2025", "10:00 AM"), never truncating it.
  dateColumn: {
    width: undefined,
    minWidth: 56,
    flexShrink: 0,
  },
  startTime: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  endTime: {
    ...typography.caption,
    fontSize: 13,
    lineHeight: 18,
    color: colors.textMuted,
  },
  content: {
    flex: 1,
    gap: 2,
  },
  petName: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  detail: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  note: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  noteText: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
    flexShrink: 1,
  },
  tags: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.xs,
    marginTop: spacing.xs,
  },
  tag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    paddingVertical: 2,
    paddingHorizontal: spacing.sm,
    borderRadius: 999,
    backgroundColor: colors.surfaceSoft,
    maxWidth: '100%',
  },
  tagText: {
    fontSize: 13,
    lineHeight: 18,
    fontWeight: '600',
    color: colors.textPrimary,
    flexShrink: 1,
  },
  chevron: {
    alignSelf: 'center',
  },
});

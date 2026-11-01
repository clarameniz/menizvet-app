import { ScrollView, StyleSheet, Text, View } from 'react-native';

import { ChoiceChip } from '@/components/design-system/choice-chip';
import { DateChip } from '@/components/design-system/date-chip';
import { formatCandidateDateLabel, formatCandidateDateParts } from '@/lib/appointment-time';
import {
  candidateKey,
  candidatesForDate,
  distinctSortedCandidateDates,
  formatCandidateTime,
  isSameCandidate,
  type CandidateIdentity,
} from '@/lib/candidate-selection';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type CandidateDateTimePickerProps<T extends CandidateIdentity> = {
  /** The loaded candidates; only their dates are offered, in ascending order. */
  candidates: readonly T[];
  selectedDate: string | null;
  selectedCandidate: CandidateIdentity | null;
  onSelectDate: (localDate: string) => void;
  /** Receives the exact candidate object that was offered. */
  onSelectCandidate: (candidate: T) => void;
  /** Section header (and radio-group name) of the date chips. */
  dateLabel: string;
  /** Section header (and radio-group name) of the time chips. */
  timeLabel: string;
  locale: string;
};

/**
 * Stateless candidate date/time picker: a full-bleed, horizontally scrollable
 * row of date chips (only dates that have candidates), then — once a date is
 * selected — a wrapping grid of that date's times. Both rows are radio groups.
 *
 * Renders two sibling sections, so the screen's own spacing between sections
 * applies. It knows nothing about who is choosing, which read produced the
 * candidates, windows, or submission: the screen owns all state, loading,
 * empty and error presentation.
 */
export function CandidateDateTimePicker<T extends CandidateIdentity>({
  candidates,
  selectedDate,
  selectedCandidate,
  onSelectDate,
  onSelectCandidate,
  dateLabel,
  timeLabel,
  locale,
}: CandidateDateTimePickerProps<T>) {
  return (
    <>
      <View style={styles.section}>
        <Text style={styles.sectionTitle} accessibilityRole="header">
          {dateLabel}
        </Text>
        {/* Full-bleed horizontal row: scrolls to the screen edge instead of
            being clipped by the page padding. */}
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={styles.dateScroller}
          contentContainerStyle={styles.dateRow}
          accessibilityRole="radiogroup"
          accessibilityLabel={dateLabel}
        >
          {distinctSortedCandidateDates(candidates).map((localDate) => {
            const { weekday, dayMonth } = formatCandidateDateParts(localDate, locale);
            return (
              <DateChip
                key={localDate}
                weekday={weekday}
                dayMonth={dayMonth}
                accessibilityLabel={formatCandidateDateLabel(localDate, locale)}
                selected={localDate === selectedDate}
                onPress={() => onSelectDate(localDate)}
              />
            );
          })}
        </ScrollView>
      </View>

      {selectedDate !== null ? (
        <View style={styles.section}>
          <Text style={styles.sectionTitle} accessibilityRole="header">
            {timeLabel}
          </Text>
          <View
            style={styles.timeGrid}
            accessibilityRole="radiogroup"
            accessibilityLabel={timeLabel}
          >
            {candidatesForDate(candidates, selectedDate).map((candidate) => (
              <ChoiceChip
                key={candidateKey(candidate)}
                label={formatCandidateTime(candidate.localTime)}
                selected={
                  selectedCandidate !== null && isSameCandidate(selectedCandidate, candidate)
                }
                onPress={() => onSelectCandidate(candidate)}
              />
            ))}
          </View>
        </View>
      ) : null}
    </>
  );
}

const styles = StyleSheet.create({
  section: {
    gap: spacing.md,
  },
  sectionTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  dateScroller: {
    marginHorizontal: -spacing.screenHorizontal,
  },
  dateRow: {
    gap: spacing.sm,
    paddingHorizontal: spacing.screenHorizontal,
  },
  timeGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
});

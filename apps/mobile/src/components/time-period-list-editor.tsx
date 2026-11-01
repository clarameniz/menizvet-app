import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { Input } from '@/components/design-system/input';
import { PillButton } from '@/components/design-system/pill-button';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import {
  newPeriodDraft,
  normalizeTimeInput,
  periodIssues,
  type PeriodDraft,
  type PeriodIssue,
} from '@/lib/appointment-hours';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

const ISSUE_KEYS: Record<PeriodIssue, TranslationKey> = {
  startRequired: 'appointmentHours.issueStartRequired',
  startInvalid: 'appointmentHours.issueTimeInvalid',
  endRequired: 'appointmentHours.issueEndRequired',
  endInvalid: 'appointmentHours.issueTimeInvalid',
  order: 'appointmentHours.issueOrder',
  overlap: 'appointmentHours.issueOverlap',
};

type TimePeriodListEditorProps = {
  /** Who the periods belong to ("Lunes", "dom, 11 oct 2026") — named in every accessible label. */
  groupLabel: string;
  periods: readonly PeriodDraft[];
  onChange: (periods: PeriodDraft[]) => void;
  editable: boolean;
  /** Shown when there are no periods (e.g. "Cerrado"); omit to show nothing. */
  emptyLabel?: string;
};

/**
 * Editable list of Clinic-local time periods for one day: each period has a
 * start and an end typed as HH:MM (plain text inputs — no native picker), a
 * Remove action, and an "Add hours" action for the day. Typed values are
 * tidied on blur ("930" → "09:30"); stored values keep their exact precision
 * until the user edits them.
 *
 * Problems are shown inline per period, immediately for wrong content
 * (format, order, overlap) and for a missing time once that period has been
 * left. Purely presentational validation: the screen owns the draft and the
 * Save rule, and the backend validates again.
 */
export function TimePeriodListEditor({
  groupLabel,
  periods,
  onChange,
  editable,
  emptyLabel,
}: TimePeriodListEditorProps) {
  const { t } = useLocale();
  // Periods the user has left at least once: only then is a missing time flagged.
  const [touched, setTouched] = useState<ReadonlySet<string>>(new Set());
  const issues = periodIssues(periods);

  function update(id: string, field: 'start' | 'end', value: string) {
    onChange(periods.map((period) => (period.id === id ? { ...period, [field]: value } : period)));
  }

  function leave(id: string, field: 'start' | 'end') {
    const period = periods.find((entry) => entry.id === id);
    if (period !== undefined) {
      const normalized = normalizeTimeInput(period[field]);
      if (normalized !== period[field]) update(id, field, normalized);
    }
    setTouched((previous) => new Set(previous).add(id));
  }

  return (
    <View style={styles.container}>
      {periods.length === 0 && emptyLabel !== undefined ? (
        <Text style={styles.empty}>{emptyLabel}</Text>
      ) : null}

      {periods.map((period, index) => {
        const issue = issues[index];
        const visibleIssue =
          issue === null ||
          ((issue === 'startRequired' || issue === 'endRequired') && !touched.has(period.id))
            ? null
            : issue;
        const position = String(index + 1);

        return (
          <View key={period.id} style={styles.period}>
            <View style={styles.fields}>
              <View style={styles.field}>
                <Input
                  label={t('appointmentHours.periodStart')}
                  accessibilityLabel={t('appointmentHours.periodStartAccessibility', {
                    day: groupLabel,
                    index: position,
                  })}
                  value={period.start}
                  placeholder={t('appointmentHours.timePlaceholder')}
                  keyboardType="numbers-and-punctuation"
                  autoCorrect={false}
                  autoCapitalize="none"
                  maxLength={15}
                  editable={editable}
                  onChangeText={(text) => update(period.id, 'start', text)}
                  onBlur={() => leave(period.id, 'start')}
                />
              </View>
              <View style={styles.field}>
                <Input
                  label={t('appointmentHours.periodEnd')}
                  accessibilityLabel={t('appointmentHours.periodEndAccessibility', {
                    day: groupLabel,
                    index: position,
                  })}
                  value={period.end}
                  placeholder={t('appointmentHours.timePlaceholder')}
                  keyboardType="numbers-and-punctuation"
                  autoCorrect={false}
                  autoCapitalize="none"
                  maxLength={15}
                  editable={editable}
                  onChangeText={(text) => update(period.id, 'end', text)}
                  onBlur={() => leave(period.id, 'end')}
                />
              </View>
              {editable ? (
                <Pressable
                  onPress={() => onChange(periods.filter((entry) => entry.id !== period.id))}
                  accessibilityRole="button"
                  accessibilityLabel={t('appointmentHours.removePeriodAccessibility', {
                    day: groupLabel,
                    index: position,
                  })}
                  style={({ pressed }) => [styles.remove, pressed && styles.removePressed]}
                >
                  <Text style={styles.removeLabel}>{t('appointmentHours.removePeriod')}</Text>
                </Pressable>
              ) : null}
            </View>
            {visibleIssue !== null ? (
              <Text style={styles.issue} accessibilityLiveRegion="polite">
                {t(ISSUE_KEYS[visibleIssue])}
              </Text>
            ) : null}
          </View>
        );
      })}

      {editable ? (
        <View style={styles.add}>
          <PillButton
            icon="add"
            label={t('appointmentHours.addPeriod')}
            accessibilityLabel={t('appointmentHours.addPeriodAccessibility', { day: groupLabel })}
            onPress={() => onChange([...periods, newPeriodDraft()])}
          />
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: spacing.sm,
  },
  empty: {
    ...typography.body,
    color: colors.textSecondary,
  },
  period: {
    gap: spacing.xs,
  },
  fields: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: spacing.sm,
  },
  field: {
    flex: 1,
  },
  remove: {
    minHeight: 52,
    minWidth: 44,
    paddingHorizontal: spacing.sm,
    justifyContent: 'center',
    alignItems: 'center',
    borderRadius: radius.medium,
  },
  removePressed: {
    backgroundColor: colors.errorSoft,
  },
  removeLabel: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.errorDark,
  },
  issue: {
    ...typography.caption,
    color: colors.errorDark,
  },
  add: {
    alignItems: 'flex-start',
  },
});

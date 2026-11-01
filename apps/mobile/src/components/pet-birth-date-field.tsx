import { StyleSheet, Text, View } from 'react-native';

import { ChoiceChip } from '@/components/design-system/choice-chip';
import { Input } from '@/components/design-system/input';
import { useLocale } from '@/i18n/locale-provider';
import type { BirthDateFormValue, BirthDateMode } from '@/lib/pet-date';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type PetBirthDateFieldProps = {
  value: BirthDateFormValue;
  onChange: (value: BirthDateFormValue) => void;
};

const MODES: readonly BirthDateMode[] = ['unknown', 'exact', 'approximate'];

/**
 * Functional date-entry UX (three separate numeric fields), not a native
 * date picker: this project has no date-picker component, and none is used
 * here deliberately. Design System v1 presentation only —
 * mode chips and `Input`s over the exact same value/onChange contract.
 *
 * The three-way mode choice (unknown/exact/approximate) mirrors the actual
 * backend model: date_of_birth and approximate_date_of_birth are two
 * separate nullable columns that are mutually exclusive
 * (pets_birth_date_exclusivity_check), not a boolean flag alongside one
 * date. Database terminology ("approximate_date_of_birth") is never shown;
 * only localized product wording is.
 */
export function PetBirthDateField({ value, onChange }: PetBirthDateFieldProps) {
  const { t } = useLocale();

  const modeLabel: Record<BirthDateMode, string> = {
    unknown: t('petForm.birthDateUnknown'),
    exact: t('petForm.birthDateExact'),
    approximate: t('petForm.birthDateApproximate'),
  };

  return (
    <View style={styles.container}>
      <Text style={styles.label}>{t('petForm.birthDateLabel')}</Text>

      <View
        style={styles.modeRow}
        accessibilityRole="radiogroup"
        accessibilityLabel={t('petForm.birthDateLabel')}
      >
        {MODES.map((mode) => (
          <ChoiceChip
            key={mode}
            label={modeLabel[mode]}
            selected={value.mode === mode}
            onPress={() => onChange({ ...value, mode })}
          />
        ))}
      </View>

      {value.mode === 'approximate' && (
        <Text style={styles.help}>{t('petForm.birthDateApproximateHelp')}</Text>
      )}

      {value.mode !== 'unknown' && (
        <View style={styles.dateRow}>
          <View style={styles.dateInputWrapper}>
            <Input
              label={t('petForm.birthDateDay')}
              keyboardType="number-pad"
              maxLength={2}
              value={value.day}
              onChangeText={(day) => onChange({ ...value, day })}
            />
          </View>
          <View style={styles.dateInputWrapper}>
            <Input
              label={t('petForm.birthDateMonth')}
              keyboardType="number-pad"
              maxLength={2}
              value={value.month}
              onChangeText={(month) => onChange({ ...value, month })}
            />
          </View>
          <View style={styles.yearInputWrapper}>
            <Input
              label={t('petForm.birthDateYear')}
              keyboardType="number-pad"
              maxLength={4}
              value={value.year}
              onChangeText={(year) => onChange({ ...value, year })}
            />
          </View>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignSelf: 'stretch',
    gap: spacing.sm,
  },
  // Same label treatment as `Input`'s own label, so this group reads as one
  // more field in the form.
  label: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  modeRow: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: spacing.sm,
  },
  help: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  dateRow: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  dateInputWrapper: {
    flex: 1,
  },
  // Four digits instead of two — a little wider so the year is never cramped.
  yearInputWrapper: {
    flex: 1.4,
  },
});

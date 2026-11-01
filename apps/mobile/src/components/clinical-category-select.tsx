import { Ionicons } from '@expo/vector-icons';
import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { CLINICAL_RECORD_CATEGORIES } from '@/data/appointment-clinical-record';
import type { ClinicalRecordEntryCategory } from '@/data/clinical-history';
import { useLocale } from '@/i18n/locale-provider';
import { categoryLabelKey } from '@/lib/clinical-history-display';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ClinicalCategorySelectProps = {
  value: ClinicalRecordEntryCategory | null;
  onChange: (category: ClinicalRecordEntryCategory) => void;
  error?: string;
  disabled?: boolean;
};

/**
 * The compact category selector of the clinical record editor (SPEC-MED-010
 * Part F): one field showing the chosen category — or a prompt, since nothing
 * is preselected — that opens the list of categories in place. Choosing one
 * closes the list. No native picker and no modal: the list stays inside the
 * editor, so the typed text around it is never hidden.
 */
export function ClinicalCategorySelect({
  value,
  onChange,
  error,
  disabled = false,
}: ClinicalCategorySelectProps) {
  const { t } = useLocale();
  const [open, setOpen] = useState(false);
  const label = t('clinicalRecord.categoryLabel');
  const shown = value === null ? t('clinicalRecord.categoryPrompt') : t(categoryLabelKey(value));

  return (
    <View style={styles.group}>
      <Text style={styles.label}>{label}</Text>
      <Pressable
        onPress={() => setOpen((current) => !current)}
        disabled={disabled}
        accessibilityRole="button"
        accessibilityLabel={`${label}: ${shown}`}
        accessibilityHint={t('clinicalRecord.categoryHint')}
        accessibilityState={{ expanded: open, disabled }}
        style={({ pressed }) => [
          styles.field,
          error !== undefined && styles.fieldError,
          pressed && styles.pressed,
        ]}
      >
        <Text style={[styles.value, value === null && styles.placeholder]}>{shown}</Text>
        <Ionicons
          name={open ? 'chevron-up' : 'chevron-down'}
          size={18}
          color={colors.textSecondary}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
        />
      </Pressable>
      {open ? (
        <View style={styles.list} accessibilityRole="radiogroup" accessibilityLabel={label}>
          {CLINICAL_RECORD_CATEGORIES.map((category) => {
            const selected = category === value;
            return (
              <Pressable
                key={category}
                onPress={() => {
                  onChange(category);
                  setOpen(false);
                }}
                disabled={disabled}
                accessibilityRole="radio"
                accessibilityLabel={t(categoryLabelKey(category))}
                accessibilityState={{ selected, checked: selected, disabled }}
                style={({ pressed }) => [styles.option, pressed && styles.pressed]}
              >
                <Text style={[styles.optionText, selected && styles.optionSelected]}>
                  {t(categoryLabelKey(category))}
                </Text>
                {selected ? (
                  <Ionicons
                    name="checkmark"
                    size={18}
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
      {error !== undefined ? (
        <Text style={styles.error} accessibilityRole="alert">
          {error}
        </Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  group: { gap: spacing.xs },
  label: { ...typography.bodyStrong, color: colors.textPrimary },
  field: {
    minHeight: 48,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
  },
  fieldError: { borderColor: colors.errorDark },
  pressed: { backgroundColor: colors.surfaceSoft },
  value: { ...typography.body, color: colors.textPrimary, flexShrink: 1 },
  placeholder: { color: colors.textSecondary },
  list: {
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    overflow: 'hidden',
  },
  option: {
    minHeight: 44,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
  },
  optionText: { ...typography.body, color: colors.textPrimary, flexShrink: 1 },
  optionSelected: { fontWeight: '700' },
  error: { ...typography.caption, color: colors.errorDark },
});

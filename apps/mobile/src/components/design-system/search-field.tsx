import { Ionicons } from '@expo/vector-icons';
import { useState } from 'react';
import { Pressable, StyleSheet, TextInput, View } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type SearchFieldProps = {
  value: string;
  onChangeText: (value: string) => void;
  /** Clears the field; shown only while it has text. */
  onClear: () => void;
  /** Optional: search now, without waiting for the pause after typing. */
  onSubmit?: () => void;
  placeholder: string;
  /** The field's accessible name (the placeholder is not announced reliably). */
  accessibilityLabel: string;
  clearAccessibilityLabel: string;
  maxLength?: number;
};

/**
 * Compact one-line search above a list: a magnifier, the text and, while
 * there is text, a clear button. Lighter than `Input` (no label row) and
 * 44pt tall; the parent decides when the text is searched.
 */
export function SearchField({
  value,
  onChangeText,
  onClear,
  onSubmit,
  placeholder,
  accessibilityLabel,
  clearAccessibilityLabel,
  maxLength,
}: SearchFieldProps) {
  const [isFocused, setIsFocused] = useState(false);

  return (
    <View style={[styles.field, isFocused && styles.fieldFocused]}>
      <Ionicons
        name="search-outline"
        size={18}
        color={colors.textSecondary}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      />
      <TextInput
        value={value}
        onChangeText={onChangeText}
        onSubmitEditing={onSubmit}
        placeholder={placeholder}
        placeholderTextColor={colors.textSecondary}
        accessibilityLabel={accessibilityLabel}
        accessibilityRole="search"
        returnKeyType="search"
        autoCapitalize="none"
        autoCorrect={false}
        maxLength={maxLength}
        onFocus={() => setIsFocused(true)}
        onBlur={() => setIsFocused(false)}
        style={styles.input}
      />
      {value.length > 0 ? (
        <Pressable
          onPress={onClear}
          accessibilityRole="button"
          accessibilityLabel={clearAccessibilityLabel}
          hitSlop={8}
          style={({ pressed }) => [styles.clear, pressed && styles.clearPressed]}
        >
          <Ionicons name="close-circle" size={18} color={colors.textSecondary} />
        </Pressable>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  field: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    minHeight: 44,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    paddingLeft: spacing.md,
    paddingRight: spacing.xs,
  },
  fieldFocused: {
    borderColor: colors.primary,
  },
  input: {
    flex: 1,
    ...typography.body,
    color: colors.textPrimary,
    paddingVertical: spacing.sm,
    paddingHorizontal: 0,
  },
  clear: {
    width: 36,
    height: 36,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.pill,
  },
  clearPressed: {
    backgroundColor: colors.surfaceSoft,
  },
});

import { Ionicons } from '@expo/vector-icons';
import { useState, type ReactNode } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View, type TextInputProps } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type InputProps = TextInputProps & {
  label: string;
  /** Concise inline error — puts the error-token border on the field itself
   * and a short message below it. Omit when there's nothing field-specific
   * to show (e.g. a server/auth error already surfaced elsewhere). */
  error?: string;
  /** Optional trailing control inside the field (e.g. `PasswordToggle`). */
  rightElement?: ReactNode;
  /**
   * Appends a plain " *" to the visible label, hidden from screen readers so
   * it is never read as "asterisk". Pass a translated `accessibilityLabel`
   * that says the field is required (e.g. "Nombre, obligatorio").
   */
  required?: boolean;
};

/**
 * Design System v1 text input. First real shared use: Sign In and Register.
 * Deliberately minimal — label, field, optional trailing element, optional
 * inline error — not a generic form framework.
 */
export function Input({
  label,
  error,
  rightElement,
  style,
  onFocus,
  onBlur,
  editable,
  multiline,
  required = false,
  ...rest
}: InputProps) {
  const [isFocused, setIsFocused] = useState(false);
  const isDisabled = editable === false;

  return (
    <View style={styles.container}>
      <View style={styles.labelRow}>
        <Text style={styles.label}>{label}</Text>
        {required ? (
          <Text style={styles.label} accessibilityElementsHidden importantForAccessibility="no">
            {' *'}
          </Text>
        ) : null}
      </View>
      <View
        style={[
          styles.field,
          multiline && styles.fieldMultiline,
          isFocused && styles.fieldFocused,
          !!error && styles.fieldError,
          isDisabled && styles.fieldDisabled,
        ]}
      >
        <TextInput
          style={[styles.input, multiline && styles.inputMultiline, style]}
          placeholderTextColor={colors.textSecondary}
          accessibilityLabel={label}
          editable={editable}
          multiline={multiline}
          onFocus={(event) => {
            setIsFocused(true);
            onFocus?.(event);
          }}
          onBlur={(event) => {
            setIsFocused(false);
            onBlur?.(event);
          }}
          {...rest}
        />
        {rightElement}
      </View>
      {error ? <Text style={styles.errorText}>{error}</Text> : null}
    </View>
  );
}

type PasswordToggleProps = {
  visible: boolean;
  onToggle: () => void;
  /** Accessible labels for the two states — caller supplies translated
   * strings (`common.showPassword` / `common.hidePassword`). */
  showLabel: string;
  hideLabel: string;
};

/** Trailing eye/eye-off control for a password `Input`. Purely a local
 * masking toggle — never touches the field's value or auth semantics. */
export function PasswordToggle({ visible, onToggle, showLabel, hideLabel }: PasswordToggleProps) {
  return (
    <Pressable
      onPress={onToggle}
      accessibilityRole="button"
      accessibilityLabel={visible ? hideLabel : showLabel}
      hitSlop={8}
      style={styles.passwordToggle}
    >
      <Ionicons
        name={visible ? 'eye-off-outline' : 'eye-outline'}
        size={20}
        color={colors.textSecondary}
      />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: {
    alignSelf: 'stretch',
    gap: spacing.xs,
  },
  labelRow: {
    flexDirection: 'row',
  },
  label: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textPrimary,
  },
  field: {
    flexDirection: 'row',
    alignItems: 'center',
    height: 52,
    borderWidth: 1.5,
    borderColor: colors.border,
    borderRadius: radius.medium,
    backgroundColor: colors.surface,
    paddingHorizontal: spacing.md,
  },
  // Grows with its content instead of clipping it inside the fixed
  // single-line height; text starts at the top-left like a text area.
  fieldMultiline: {
    height: undefined,
    minHeight: 104,
    alignItems: 'flex-start',
    paddingVertical: spacing.md,
  },
  fieldFocused: {
    borderColor: colors.primary,
  },
  fieldError: {
    borderColor: colors.error,
  },
  fieldDisabled: {
    backgroundColor: colors.surfaceSoft,
    opacity: 0.7,
  },
  input: {
    flex: 1,
    height: '100%',
    ...typography.body,
    color: colors.textPrimary,
    padding: 0,
  },
  inputMultiline: {
    height: undefined,
    minHeight: 80,
    textAlignVertical: 'top',
  },
  errorText: {
    ...typography.caption,
    color: colors.error,
  },
  passwordToggle: {
    paddingLeft: spacing.sm,
  },
});

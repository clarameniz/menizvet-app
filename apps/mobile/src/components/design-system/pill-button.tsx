import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type PillButtonProps = {
  icon: ComponentProps<typeof Ionicons>['name'];
  label: string;
  onPress: () => void;
  loading?: boolean;
  /**
   * Adds a soft shadow for pills floating over a busy surface (the Discovery
   * map). Flat (border only) everywhere else.
   */
  floating?: boolean;
  /**
   * Renders a 44×44 circle with just the icon (the Discovery map's "My
   * location" control). `label` is then not shown visually but is still the
   * accessible name, so it must always be passed.
   */
  iconOnly?: boolean;
  /** Defaults to `label`; pass a fuller phrase when the visible label needs context. */
  accessibilityLabel?: string;
};

/**
 * Compact icon + label secondary action (Discovery's navigation/utility
 * shortcuts: Near me / View map / Use my location / Search this area). Kept
 * deliberately lighter than `Button` — these are utilities, never a
 * screen's primary action. ≥44pt tall.
 */
export function PillButton({
  icon,
  label,
  onPress,
  loading = false,
  floating = false,
  iconOnly = false,
  accessibilityLabel,
}: PillButtonProps) {
  return (
    <Pressable
      onPress={onPress}
      disabled={loading}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? label}
      accessibilityState={{ disabled: loading, busy: loading }}
      style={({ pressed }) => [
        styles.pill,
        iconOnly && styles.iconOnly,
        floating && styles.floating,
        pressed && !loading && styles.pressed,
      ]}
    >
      {loading ? (
        <ActivityIndicator size="small" color={colors.primary} />
      ) : (
        <Ionicons name={icon} size={iconOnly ? 20 : 18} color={colors.primary} />
      )}
      {iconOnly ? null : (
        <Text style={styles.label} numberOfLines={1}>
          {label}
        </Text>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  pill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    minHeight: 44,
    paddingHorizontal: spacing.lg,
    borderRadius: radius.pill,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
  iconOnly: {
    width: 44,
    height: 44,
    paddingHorizontal: 0,
    justifyContent: 'center',
  },
  floating: {
    shadowColor: colors.textPrimary,
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.12,
    shadowRadius: 6,
    elevation: 3,
  },
  pressed: {
    backgroundColor: colors.primarySoft,
  },
  label: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primary,
    flexShrink: 1,
  },
});

import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps, ReactNode } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  type StyleProp,
  type ViewStyle,
} from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ActionProps = {
  icon: ComponentProps<typeof Ionicons>['name'];
  accessibilityLabel: string;
  onPress: () => void;
  disabled?: boolean;
  loading?: boolean;
  destructive?: boolean;
  /** For an action that shows or hides content in place ("View changes"). */
  expanded?: boolean;
};

/**
 * A light icon + short label action of a list card (card footer, section
 * header) — never a screen's primary action. ≥44pt tall.
 */
export function CompactAction({ label, ...props }: ActionProps & { label: string }) {
  return (
    <ActionPressable {...props} style={styles.action}>
      <Text style={[styles.actionLabel, props.destructive && styles.destructiveLabel]}>
        {label}
      </Text>
    </ActionPressable>
  );
}

/** A 44×44 icon-only row action; its accessible name says what it acts on. */
export function RowIconAction(props: ActionProps) {
  return <ActionPressable {...props} style={styles.iconAction} />;
}

function ActionPressable({
  icon,
  accessibilityLabel,
  onPress,
  disabled = false,
  loading = false,
  destructive = false,
  expanded,
  style,
  children,
}: ActionProps & { style: StyleProp<ViewStyle>; children?: ReactNode }) {
  const isDisabled = disabled || loading;
  const color = destructive ? colors.errorDark : colors.primary;
  return (
    <Pressable
      onPress={onPress}
      disabled={isDisabled}
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled: isDisabled, busy: loading, expanded }}
      style={({ pressed }) => [
        style,
        expanded && styles.expanded,
        isDisabled && !loading && styles.disabled,
        pressed && !isDisabled && styles.pressed,
      ]}
    >
      {loading ? (
        <ActivityIndicator size="small" color={color} />
      ) : (
        <Ionicons name={icon} size={20} color={color} />
      )}
      {children}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  action: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    minHeight: 44,
    paddingHorizontal: spacing.sm,
    borderRadius: radius.medium,
  },
  iconAction: {
    width: 44,
    height: 44,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: radius.medium,
  },
  actionLabel: { ...typography.caption, fontWeight: '600', color: colors.primary },
  destructiveLabel: { color: colors.errorDark },
  // The content it shows is open: the action stays visibly "on".
  expanded: { backgroundColor: colors.primarySoft },
  disabled: { opacity: 0.5 },
  pressed: { backgroundColor: colors.primarySoft },
});

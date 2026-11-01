import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Design System v1 tab selector under a screen's header, in the chips'
 * language: the selected tab is filled teal with bold white text, so selection
 * never relies on color alone, and it is announced as a selected tab. ≥44dp
 * tall; grows with font scale instead of clipping. Selecting a tab only changes
 * the view; each view decides what it reads.
 */
export function TabSelector<T extends string>({
  tabs,
  selected,
  onSelect,
  testIDPrefix,
}: {
  /** Already-localized labels, in display order. */
  tabs: readonly { value: T; label: string }[];
  selected: T;
  onSelect: (tab: T) => void;
  /** Each tab gets `${testIDPrefix}-${value}`. */
  testIDPrefix: string;
}) {
  return (
    <View style={styles.bar} accessibilityRole="tablist">
      {tabs.map(({ value, label }) => {
        const isSelected = value === selected;
        return (
          <Pressable
            key={value}
            onPress={() => onSelect(value)}
            accessibilityRole="tab"
            accessibilityLabel={label}
            accessibilityState={{ selected: isSelected }}
            testID={`${testIDPrefix}-${value}`}
            style={({ pressed }) => [
              styles.tab,
              isSelected && styles.selected,
              pressed && !isSelected && styles.pressed,
            ]}
          >
            <Text style={[styles.label, isSelected && styles.labelSelected]} numberOfLines={1}>
              {label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: 'row',
    gap: spacing.xs,
    padding: spacing.xs,
    borderRadius: radius.medium,
    borderWidth: 1,
    borderColor: colors.border,
    backgroundColor: colors.surface,
  },
  tab: {
    flex: 1,
    minHeight: 44,
    paddingHorizontal: spacing.sm,
    paddingVertical: spacing.sm,
    borderRadius: radius.small,
    alignItems: 'center',
    justifyContent: 'center',
  },
  selected: {
    backgroundColor: colors.primary,
  },
  pressed: {
    backgroundColor: colors.primarySoft,
  },
  label: {
    ...typography.caption,
    fontWeight: '500',
    color: colors.textPrimary,
    textAlign: 'center',
  },
  labelSelected: {
    fontWeight: '700',
    color: colors.surface,
  },
});

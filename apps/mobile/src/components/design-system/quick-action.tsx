import type { ReactNode } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';

type QuickActionProps = {
  icon: ReactNode;
  label: string;
  /**
   * Overrides the accessible name announced to screen readers, without
   * changing the visible label. Use this when the short visible label alone
   * could be misread as promising more than the destination actually shows
   * (e.g. "Check availability" must not be read as implying live bookable
   * slots) — the fuller, disambiguating phrase only needs to reach
   * assistive tech, not add a second line of visible copy to every tile.
   * Defaults to `label`.
   */
  accessibilityLabel?: string;
  onPress: () => void;
};

/**
 * Compact icon-over-label tile for the public home's three-across quick
 * action row. Deliberately minimal (no description copy) — the whole point
 * is replacing what used to be several full description cards with one
 * compact row plus the primary discovery card above it.
 */
export function QuickAction({ icon, label, accessibilityLabel, onPress }: QuickActionProps) {
  const content = (
    <View style={styles.tile}>
      <View
        style={styles.iconWrap}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        {icon}
      </View>
      {/* Labels use curated `\n` breaks (short, fixed navigation copy, not
          dynamic content) so the line break itself is intentional rather
          than left to word-wrap — `numberOfLines` stays as a safety net,
          not the primary control. */}
      <Text style={styles.label} numberOfLines={2}>
        {label}
      </Text>
    </View>
  );

  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={(accessibilityLabel ?? label).replace(/\n/g, ' ')}
      style={({ pressed }) => [styles.touchable, pressed && styles.pressed]}
    >
      {content}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  touchable: {
    flex: 1,
  },
  pressed: {
    opacity: 0.85,
  },
  tile: {
    alignItems: 'center',
    gap: spacing.xs,
    // `surfaceSoft` sat almost flush against the page background (barely
    // perceptible) — `border` gives real, visible contrast while staying
    // inside the same muted palette.
    backgroundColor: colors.border,
    borderRadius: radius.medium,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.xs,
  },
  iconWrap: {
    width: 30,
    height: 30,
    alignItems: 'center',
    justifyContent: 'center',
  },
  label: {
    // Bespoke size, not a shared typography token — closer to the "Modern
    // Premium" reference's compact tile labels (~14-15px, semibold, tight
    // line-height) than any of the existing named tokens fit.
    fontSize: 14,
    lineHeight: 18,
    fontWeight: '600',
    color: colors.textPrimary,
    textAlign: 'center',
  },
});

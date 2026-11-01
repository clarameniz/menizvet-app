import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';

import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/** `location`: a device-location prompt or outcome (Nearby) — informational, not an error. */
type StateMessageTone = 'loading' | 'empty' | 'error' | 'location';

type StateMessageProps = {
  tone: StateMessageTone;
  message: string;
  /** Overrides the tone's default icon (e.g. a paw for "no pets yet"). Ignored while loading. */
  icon?: ComponentProps<typeof Ionicons>['name'];
  /** Optional short bold line above `message`, for states that had their own heading. */
  title?: string;
};

const ICONS: Record<
  Exclude<StateMessageTone, 'loading'>,
  ComponentProps<typeof Ionicons>['name']
> = {
  empty: 'search-outline',
  error: 'alert-circle-outline',
  location: 'location-outline',
};

/**
 * Design System v1 presentation for a screen-level loading / empty / error
 * state: one soft icon badge (or spinner) over one line of already-localized
 * copy. Presentation only — callers still own which state they're in and
 * which localized message (never a raw backend error) to show.
 */
export function StateMessage({ tone, message, icon, title }: StateMessageProps) {
  return (
    <View
      style={styles.container}
      accessibilityLiveRegion={tone === 'error' ? 'polite' : 'none'}
      accessibilityRole={tone === 'error' ? 'alert' : undefined}
    >
      <View
        style={[styles.badge, tone === 'error' && styles.badgeError]}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        {tone === 'loading' ? (
          <ActivityIndicator color={colors.primary} />
        ) : (
          <Ionicons
            name={icon ?? ICONS[tone]}
            size={24}
            color={tone === 'error' ? colors.error : colors.primary}
          />
        )}
      </View>
      <View style={styles.textBlock}>
        {title ? <Text style={styles.title}>{title}</Text> : null}
        <Text style={styles.message}>{message}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: spacing.xxl,
    paddingHorizontal: spacing.lg,
  },
  badge: {
    width: 48,
    height: 48,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  badgeError: {
    backgroundColor: colors.errorSoft,
  },
  textBlock: {
    alignItems: 'center',
    gap: spacing.xs,
  },
  title: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
    textAlign: 'center',
  },
  message: {
    ...typography.body,
    color: colors.textSecondary,
    textAlign: 'center',
  },
});

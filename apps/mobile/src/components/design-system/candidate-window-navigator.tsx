import { StyleSheet, Text, View } from 'react-native';

import { Button } from '@/components/design-system/button';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type CandidateWindowNavigatorProps = {
  /** The dates of the window on screen, already formatted ("6 Mar 2035 to 4 May 2035"). */
  label: string;
  earlierLabel: string;
  laterLabel: string;
  /** Moves to the earlier window; `null` hides the action (no earlier window). */
  onEarlier: (() => void) | null;
  /** Moves to the later window; `null` hides the action (no later window). */
  onLater: (() => void) | null;
  disabled?: boolean;
};

/**
 * Stateless "Earlier dates" / "Later dates" navigation between candidate date
 * windows, under a label naming the window on screen. Which windows exist —
 * their size, first date, and whether there is a limit — belongs to each flow;
 * this only shows the actions the flow offers.
 */
export function CandidateWindowNavigator({
  label,
  earlierLabel,
  laterLabel,
  onEarlier,
  onLater,
  disabled = false,
}: CandidateWindowNavigatorProps) {
  return (
    <View style={styles.navigator}>
      <Text style={styles.label}>{label}</Text>
      {onEarlier !== null || onLater !== null ? (
        <View style={styles.buttons}>
          {onEarlier !== null ? (
            <View style={styles.button}>
              <Button
                variant="secondary"
                label={earlierLabel}
                onPress={onEarlier}
                disabled={disabled}
              />
            </View>
          ) : null}
          {onLater !== null ? (
            <View style={styles.button}>
              <Button
                variant="secondary"
                label={laterLabel}
                onPress={onLater}
                disabled={disabled}
              />
            </View>
          ) : null}
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  navigator: {
    gap: spacing.sm,
  },
  label: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.textSecondary,
  },
  buttons: {
    flexDirection: 'row',
    gap: spacing.sm,
  },
  button: {
    flex: 1,
  },
});

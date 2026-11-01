import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { ChevronMark } from '@/components/design-system/icon';
import type { Pet } from '@/data/pets';
import { petSummary } from '@/lib/pet-summary';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type PetCardProps = {
  pet: Pet;
  /**
   * Overrides the default "open this Pet's detail" navigation — e.g.
   * Appointments' pet selection, which picks a Pet in place instead.
   */
  onPress?: () => void;
};

/**
 * Design System v1 My Pets row (replaces the legacy `PetListItem`, same
 * behavior): whole card pressable, pushes `/pets/[id]`, only renders fields
 * get_my_pets() returns; no per-row backend call. The avatar is one neutral
 * paw for every Pet: species is free text in the backend (no enum), so
 * mapping it to per-species icons would be guesswork, and
 * profile_image_reference is never rendered (see src/data/pets.ts).
 */
export function PetCard({ pet, onPress }: PetCardProps) {
  const summary = petSummary(pet);

  return (
    <Pressable
      onPress={onPress ?? (() => router.push(`/pets/${pet.id}`))}
      accessibilityRole="button"
      accessibilityLabel={`${pet.name}, ${summary}`}
      style={({ pressed }) => [styles.card, pressed && styles.pressed]}
    >
      <PetAvatar />
      <View style={styles.textWrap}>
        <Text style={styles.name}>{pet.name}</Text>
        <Text style={styles.summary} numberOfLines={1}>
          {summary}
        </Text>
      </View>
      <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
        <ChevronMark color={colors.textSecondary} size={20} />
      </View>
    </Pressable>
  );
}

/** Decorative paw badge shared by the Pet card and the Pet detail header. */
export function PetAvatar({ size = 44 }: { size?: number }) {
  return (
    <View
      style={[styles.avatar, { width: size, height: size }]}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
    >
      <Ionicons name="paw-outline" size={Math.round(size * 0.5)} color={colors.primary} />
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    paddingVertical: spacing.md,
    paddingHorizontal: spacing.lg,
  },
  pressed: {
    backgroundColor: colors.surfaceSoft,
  },
  avatar: {
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  textWrap: {
    flex: 1,
    gap: 2,
  },
  name: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  summary: {
    ...typography.caption,
    color: colors.textSecondary,
  },
});

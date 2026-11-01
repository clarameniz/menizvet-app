import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import { ChevronMark } from '@/components/design-system/icon';
import type { ClinicPublicProfile } from '@/data/clinics';
import { useLocale } from '@/i18n/locale-provider';
import { formatDistanceMeters } from '@/lib/discovery-viewport';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type ClinicCardProps = {
  clinic: Pick<ClinicPublicProfile, 'clinicId' | 'displayName' | 'description'>;
  /**
   * The Clinic's published Location address — returned by every list read
   * (Clinic list, Nearby, Map) when the Clinic has a Location. When present
   * it replaces the description as the supporting line: where a clinic is
   * matters more than its blurb here.
   */
  addressText?: string;
  /** Nearby results only — discover_nearby_clinics' own distance_meters, never computed client-side. */
  distanceMeters?: number;
};

/**
 * Design System v1 "Clinic public summary" card, shared by the Clinic list
 * (SPEC-DIS-004 §5), Nearby list and the Map's selected-marker card
 * (SPEC-DIS-003 BR-12/BR-13).
 * Whole card pressable, pushes `/clinics/[id]`; only renders fields the
 * approved public reads return (no ratings, photos or availability) and no
 * per-row backend call.
 */
export function ClinicCard({ clinic, addressText, distanceMeters }: ClinicCardProps) {
  const { t } = useLocale();
  const name = clinic.displayName ?? t('discoveryList.unnamedClinic');
  const formattedDistance =
    distanceMeters !== undefined ? formatDistanceMeters(distanceMeters) : null;
  const distanceLabel = formattedDistance
    ? t(formattedDistance.key, { count: formattedDistance.count })
    : null;
  const supportingText = addressText ?? clinic.description;

  return (
    <Pressable
      onPress={() => router.push(`/clinics/${clinic.clinicId}`)}
      accessibilityRole="button"
      accessibilityLabel={[name, supportingText, distanceLabel].filter(Boolean).join('. ')}
      style={({ pressed }) => [styles.card, pressed && styles.pressed]}
    >
      <View
        style={styles.iconWrap}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Ionicons name="medkit-outline" size={20} color={colors.primary} />
      </View>
      <View style={styles.textWrap}>
        <Text style={styles.name}>{name}</Text>
        {addressText ? (
          <View style={styles.addressRow}>
            <Ionicons
              name="location-outline"
              size={14}
              color={colors.primary}
              style={styles.addressIcon}
              accessibilityElementsHidden
              importantForAccessibility="no-hide-descendants"
            />
            <Text style={styles.supporting} numberOfLines={2}>
              {addressText}
            </Text>
          </View>
        ) : clinic.description ? (
          <Text style={styles.supporting} numberOfLines={2}>
            {clinic.description}
          </Text>
        ) : null}
      </View>
      <View
        style={styles.trailing}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        {distanceLabel ? <Text style={styles.distance}>{distanceLabel}</Text> : null}
        <ChevronMark color={colors.textSecondary} size={20} />
      </View>
    </Pressable>
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
  iconWrap: {
    width: 40,
    height: 40,
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
  addressRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.xs,
  },
  // Centers the 14px pin on the caption's first 20px line box.
  addressIcon: {
    marginTop: 3,
  },
  supporting: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
  },
  trailing: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
  },
  distance: {
    ...typography.caption,
    fontWeight: '600',
    color: colors.primary,
  },
});

import { StyleSheet, Text, View } from 'react-native';

import { Input } from '@/components/design-system/input';
import { PetBirthDateField } from '@/components/pet-birth-date-field';
import { useLocale } from '@/i18n/locale-provider';
import type { PetFormRawFields } from '@/lib/pet-form';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type PetProfileFieldsProps = {
  value: PetFormRawFields;
  onChange: (value: PetFormRawFields) => void;
  /**
   * Marks the always-required fields (name, species — the same two
   * validatePetFormFields enforces) with a visible "*" and a spoken
   * "required". Birth date is only conditionally required, so it is never
   * marked. Off by default; Register Pet opts in.
   */
  markRequired?: boolean;
};

/**
 * The Pet profile field set shared by the Register and Edit screens — both
 * submit the same name/species/breed/sex/birth-date/microchip/behavioral-info
 * fields with identical normalization rules (src/lib/pet-form.ts), only the
 * eventual RPC and submit semantics differ, which stay owned by each route.
 * Species and sex are kept as free text: the backend has no enum/check
 * restricting either to a finite set (public.pets.species/.sex are plain
 * `text` with only a non-blank constraint), so inventing a fixed picker here
 * would add a restriction the backend doesn't have. profile_image_reference
 * is never collected here — see src/data/pets.ts's module doc comment.
 */
export function PetProfileFields({ value, onChange, markRequired = false }: PetProfileFieldsProps) {
  const { t } = useLocale();

  // Spread only when marking: an explicit `accessibilityLabel: undefined`
  // would override Input's default (its visible label).
  const requiredProps = (label: string) =>
    markRequired
      ? { required: true, accessibilityLabel: t('petForm.requiredFieldA11y', { label }) }
      : {};

  return (
    <View style={styles.container}>
      <Input
        label={t('petForm.nameLabel')}
        autoCapitalize="words"
        value={value.name}
        onChangeText={(name) => onChange({ ...value, name })}
        {...requiredProps(t('petForm.nameLabel'))}
      />

      <Input
        label={t('petForm.speciesLabel')}
        {...requiredProps(t('petForm.speciesLabel'))}
        autoCapitalize="words"
        value={value.species}
        onChangeText={(species) => onChange({ ...value, species })}
      />

      <Input
        label={t('petForm.breedLabel')}
        autoCapitalize="words"
        value={value.breed}
        onChangeText={(breed) => onChange({ ...value, breed })}
      />

      <Input
        label={t('petForm.sexLabel')}
        autoCapitalize="words"
        value={value.sex}
        onChangeText={(sex) => onChange({ ...value, sex })}
      />

      <PetBirthDateField
        value={value.birthDate}
        onChange={(birthDate) => onChange({ ...value, birthDate })}
      />

      <Input
        label={t('petForm.microchipLabel')}
        autoCapitalize="none"
        value={value.microchip}
        onChangeText={(microchip) => onChange({ ...value, microchip })}
      />

      <View style={styles.behavioralInfoGroup}>
        <Input
          label={t('petForm.behavioralInfoLabel')}
          multiline
          numberOfLines={3}
          value={value.behavioralInfo}
          onChangeText={(behavioralInfo) => onChange({ ...value, behavioralInfo })}
          accessibilityHint={t('petForm.behavioralInfoHelp')}
        />
        <Text style={styles.help}>{t('petForm.behavioralInfoHelp')}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    gap: spacing.lg,
  },
  behavioralInfoGroup: {
    gap: spacing.xs,
  },
  help: {
    ...typography.caption,
    color: colors.textSecondary,
  },
});

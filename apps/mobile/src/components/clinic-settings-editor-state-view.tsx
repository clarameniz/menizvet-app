import { StyleSheet, View } from 'react-native';

import { Button } from '@/components/design-system/button';
import { StateMessage } from '@/components/design-system/state-message';
import type { ClinicSettingsEditorState } from '@/hooks/use-clinic-settings-editor';
import { useLocale } from '@/i18n/locale-provider';
import { spacing } from '@/theme/spacing';

type ClinicSettingsEditorStateViewProps = {
  state: Exclude<ClinicSettingsEditorState, { kind: 'loaded' }>;
  onRetry: () => void;
  onBack: () => void;
};

/**
 * The loading / error / unavailable presentation shared by the Clinic
 * settings editors, so each reacts the same way to a lost capability (or an
 * unknown Clinic), a failed first read, or an expired session.
 */
export function ClinicSettingsEditorStateView({
  state,
  onRetry,
  onBack,
}: ClinicSettingsEditorStateViewProps) {
  const { t } = useLocale();

  if (state.kind === 'loading') {
    return <StateMessage tone="loading" message={t('clinicSettings.loading')} />;
  }
  if (state.kind === 'error') {
    return (
      <View style={styles.block}>
        <StateMessage tone="error" message={t(state.messageKey)} />
        <Button label={t('professional.retry')} onPress={onRetry} />
        <Button variant="secondary" label={t('clinicSettings.backToSettings')} onPress={onBack} />
      </View>
    );
  }
  return (
    <View style={styles.block}>
      <StateMessage
        tone="empty"
        icon="settings-outline"
        message={t('clinicSettings.editorUnavailable')}
      />
      <Button variant="secondary" label={t('clinicSettings.backToSettings')} onPress={onBack} />
    </View>
  );
}

const styles = StyleSheet.create({
  block: {
    gap: spacing.md,
  },
});

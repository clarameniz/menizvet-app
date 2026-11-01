import { StyleSheet, View } from 'react-native';

import { Button } from '@/components/design-system/button';
import { StateMessage } from '@/components/design-system/state-message';
import type { AppointmentHoursState } from '@/hooks/use-appointment-hours';
import { useLocale } from '@/i18n/locale-provider';
import { spacing } from '@/theme/spacing';

type AppointmentHoursStateViewProps = {
  state: Exclude<AppointmentHoursState, { kind: 'loaded' }>;
  onRetry: () => void;
  onBack: () => void;
  backLabel: string;
};

/**
 * The loading / error / unavailable presentation shared by the Appointment
 * hours screen and its editors, so every one of them reacts the same way to
 * a lost capability, a failed first read, or a session that expired.
 */
export function AppointmentHoursStateView({
  state,
  onRetry,
  onBack,
  backLabel,
}: AppointmentHoursStateViewProps) {
  const { t } = useLocale();

  if (state.kind === 'loading') {
    return <StateMessage tone="loading" message={t('appointmentHours.loading')} />;
  }
  if (state.kind === 'error') {
    return (
      <View style={styles.block}>
        <StateMessage tone="error" message={t(state.messageKey)} />
        <Button label={t('professional.retry')} onPress={onRetry} />
        <Button variant="secondary" label={backLabel} onPress={onBack} />
      </View>
    );
  }
  return (
    <View style={styles.block}>
      <StateMessage tone="empty" icon="time-outline" message={t('appointmentHours.unavailable')} />
      <Button variant="secondary" label={backLabel} onPress={onBack} />
    </View>
  );
}

const styles = StyleSheet.create({
  block: {
    gap: spacing.md,
  },
});

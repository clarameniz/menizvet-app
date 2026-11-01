import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useRef } from 'react';
import { Alert, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { Button } from '@/components/design-system/button';
import { StateMessage } from '@/components/design-system/state-message';
import { OrganizationSubscriptionContent } from '@/components/organization-subscription-content';
import { useOrganizationSubscription } from '@/hooks/use-organization-subscription';
import { useLocale } from '@/i18n/locale-provider';
import { goBackOr } from '@/lib/navigation';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Organization Subscription status (SPEC-SUB-002 §15) for holders of
 * ORGANIZATION_MANAGE_SUBSCRIPTION. Read-only: no billing, payment, renewal
 * or provider information exists or is shown. The route Organization is
 * authorized server-side on every read.
 */
export default function OrganizationSubscriptionRoute() {
  const { organizationId } = useLocalSearchParams<{ organizationId: string | string[] }>();
  const id = typeof organizationId === 'string' ? organizationId : '';
  // A changed route owns fresh state: Org A is never rendered under Org B.
  return <SubscriptionScreen key={id} organizationId={id} />;
}

function SubscriptionScreen({ organizationId }: { organizationId: string }) {
  const { t } = useLocale();
  const { state, reload, invalidate, leave } = useOrganizationSubscription(organizationId);
  const hasShownStatus = useRef(false);
  const loseAccess = useCallback(() => {
    leave(() => {
      Alert.alert(t('subscription.title'), t('subscription.unavailable'));
      router.dismissTo('/professional');
    });
  }, [leave, t]);
  const refresh = useCallback(async () => {
    const read = await reload();
    if (read?.kind === 'loaded') hasShownStatus.current = true;
    if (read?.kind === 'unavailable' && hasShownStatus.current) loseAccess();
  }, [reload, loseAccess]);
  useFocusEffect(
    useCallback(() => {
      void refresh();
      return invalidate;
    }, [refresh, invalidate]),
  );
  const back = () => leave(() => goBackOr('/professional'));

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.content}>
        <AppTopBar onBack={back} />
        <Text style={styles.title} accessibilityRole="header">
          {t('subscription.title')}
        </Text>
        {state.kind === 'loading' ? (
          <StateMessage tone="loading" message={t('subscription.loading')} />
        ) : state.kind === 'loaded' ? (
          <OrganizationSubscriptionContent status={state.status} />
        ) : (
          <View style={styles.state}>
            <StateMessage
              tone={state.kind === 'unavailable' ? 'empty' : 'error'}
              message={t(
                state.kind === 'unavailable' ? 'subscription.unavailable' : state.messageKey,
              )}
            />
            {state.kind === 'error' ? (
              <Button
                label={t('subscription.retry')}
                onPress={() => {
                  void refresh();
                }}
              />
            ) : null}
            <Button variant="secondary" label={t('staff.backToProfessional')} onPress={back} />
          </View>
        )}
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: colors.background },
  content: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxl,
    gap: spacing.xl,
  },
  title: { ...typography.h1, color: colors.textPrimary },
  state: { gap: spacing.md },
});

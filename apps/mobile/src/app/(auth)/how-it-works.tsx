import { Ionicons } from '@expo/vector-icons';
import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import type { ComponentProps } from 'react';
import { ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { Button } from '@/components/design-system/button';
import { PublicTopBar } from '@/components/design-system/public-top-bar';
import type { TranslationKey } from '@/i18n/i18n';
import { useLocale } from '@/i18n/locale-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

type Step = {
  icon: ComponentProps<typeof Ionicons>['name'];
  titleKey: TranslationKey;
  bodyKey: TranslationKey;
};

// The real current flow only: public Discovery, then (signed in) requesting an
// Appointment for one of the Guardian's Pets, then appointments + clinical
// history. No claim about live public availability or features that don't exist.
const STEPS: readonly Step[] = [
  { icon: 'search-outline', titleKey: 'howItWorks.step1Title', bodyKey: 'howItWorks.step1Body' },
  { icon: 'calendar-outline', titleKey: 'howItWorks.step2Title', bodyKey: 'howItWorks.step2Body' },
  {
    icon: 'document-text-outline',
    titleKey: 'howItWorks.step3Title',
    bodyKey: 'howItWorks.step3Body',
  },
];

/**
 * Public "How it works", reached from the public home's quick action. Lives in
 * the (auth) group with Sign In / Register: it is a pre-login explainer, and
 * its "Create account" action only makes sense while signed out. Static
 * content — no backend reads.
 */
export default function HowItWorksScreen() {
  const { t } = useLocale();

  return (
    <SafeAreaView style={styles.safeArea}>
      {/* Light screen: explicit dark status-bar icons (the public home before
          it sets `light` over its photo hero). */}
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <PublicTopBar fallbackHref="/" />

        <View style={styles.titleBlock}>
          <Text style={styles.title} accessibilityRole="header">
            {t('howItWorks.title')}
          </Text>
          <Text style={styles.support}>{t('howItWorks.support')}</Text>
        </View>

        <View style={styles.steps}>
          {STEPS.map((step, index) => {
            const isLast = index === STEPS.length - 1;
            return (
              <View key={step.titleKey} style={styles.step}>
                {/* Left rail: icon badge + connector to the next step. */}
                <View
                  style={styles.rail}
                  accessibilityElementsHidden
                  importantForAccessibility="no-hide-descendants"
                >
                  <View style={styles.badge}>
                    <Ionicons name={step.icon} size={20} color={colors.primary} />
                  </View>
                  {isLast ? null : <View style={styles.connector} />}
                </View>
                <View style={[styles.stepText, !isLast && styles.stepTextSpaced]}>
                  <Text style={styles.stepTitle} accessibilityRole="header">
                    {t(step.titleKey)}
                  </Text>
                  <Text style={styles.stepBody}>{t(step.bodyKey)}</Text>
                </View>
              </View>
            );
          })}
        </View>

        <View style={styles.actions}>
          <Button
            label={t('publicHome.searchClinicsAction')}
            onPress={() => router.push('/clinics')}
          />
          <Button
            variant="secondary"
            label={t('publicHome.createAccountAction')}
            onPress={() => router.push('/register')}
          />
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const BADGE_SIZE = 40;

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  scrollContent: {
    flexGrow: 1,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xl,
    gap: spacing.xl,
  },
  titleBlock: {
    gap: spacing.sm,
  },
  title: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  support: {
    ...typography.body,
    color: colors.textSecondary,
  },
  steps: {
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    padding: spacing.lg,
  },
  step: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  rail: {
    alignItems: 'center',
    width: BADGE_SIZE,
  },
  badge: {
    width: BADGE_SIZE,
    height: BADGE_SIZE,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
  },
  // Fills the rest of the step's height, so it always reaches the next badge
  // however many lines the body wraps to.
  connector: {
    flex: 1,
    width: 2,
    marginVertical: spacing.xs,
    borderRadius: 1,
    backgroundColor: colors.border,
  },
  stepText: {
    flex: 1,
    gap: 2,
    paddingTop: spacing.sm,
  },
  stepTextSpaced: {
    paddingBottom: spacing.lg,
  },
  stepTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  stepBody: {
    ...typography.caption,
    color: colors.textSecondary,
  },
  // Pushed to the bottom on tall screens; directly after the steps otherwise.
  actions: {
    marginTop: 'auto',
    gap: spacing.md,
  },
});

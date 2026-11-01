import { Ionicons } from '@expo/vector-icons';
import { router, useFocusEffect, type Href } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useRef, useState, type ComponentProps } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { AppTopBar } from '@/components/design-system/app-top-bar';
import { getMyProfessionalContext } from '@/data/professional-context';
import { useLocale } from '@/i18n/locale-provider';
import { hasProfessionalOrganizations } from '@/lib/professional-context-display';
import { useSession } from '@/lib/session-provider';
import { colors } from '@/theme/colors';
import { radius } from '@/theme/radius';
import { spacing } from '@/theme/spacing';
import { typography } from '@/theme/typography';

/**
 * Authenticated home (Design System v1). Same four destinations as the
 * Milestone A placeholder it replaces — presentation only. Sign out lives in
 * Profile's Account & security section (same centralized `signOut()`,
 * session-provider.tsx), not here.
 *
 * No tab bar below this screen, so it owns every safe-area edge itself
 * (same `background` color, so the bottom inset never shows as a strip).
 *
 * Professional entry point (SPEC-ORG-007, ADR-010): get_my_professional_context()
 * is read in the background on every focus — Home never waits for it. The
 * "MenizVet Professional" tile appears only once a read for the current User
 * returned one or more current Organizations; with zero Organizations Home is
 * exactly the Guardian dashboard. Latest read wins; a failed refresh keeps
 * the last known answer (and never surfaces an error here). Only a boolean is
 * kept, in screen state tied to the User id, never persisted — sign-out
 * unmounts this route, and a different User never sees a previous User's
 * answer. Presentation only: /professional re-reads, and every professional
 * operation is authorized server-side.
 */
export default function HomeScreen() {
  const { t } = useLocale();
  const { user } = useSession();
  const accountLabel = user?.email ?? user?.id ?? t('home.unknownUser');
  const userId = user?.id ?? null;

  const [professionalAccess, setProfessionalAccess] = useState<{
    userId: string;
    hasOrganizations: boolean;
  } | null>(null);

  const isMountedRef = useRef(true);
  // Latest-load-wins: focus reloads can overlap; only the newest may write state.
  const loadSeqRef = useRef(0);

  useEffect(() => {
    isMountedRef.current = true;
    return () => {
      isMountedRef.current = false;
    };
  }, []);

  useFocusEffect(
    useCallback(() => {
      if (userId === null) return;
      const seq = ++loadSeqRef.current;

      getMyProfessionalContext().then((result) => {
        if (!isMountedRef.current || seq !== loadSeqRef.current) return;
        // Transient failure: keep whatever Home already shows.
        if (result.error !== null) return;
        setProfessionalAccess({
          userId,
          hasOrganizations: hasProfessionalOrganizations(result.data),
        });
      });
    }, [userId]),
  );

  const showProfessionalEntry =
    professionalAccess !== null &&
    professionalAccess.userId === userId &&
    professionalAccess.hasOrganizations;

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.scrollContent} showsVerticalScrollIndicator={false}>
        <AppTopBar />

        <View style={styles.greetingBlock}>
          <Text style={styles.greeting} accessibilityRole="header">
            {t('home.greeting')}
          </Text>
          <Text style={styles.support}>{t('home.support')}</Text>
          <View
            style={styles.accountRow}
            accessible
            accessibilityLabel={`${t('home.title')}: ${accountLabel}`}
          >
            <Ionicons name="person-circle-outline" size={16} color={colors.textSecondary} />
            <Text style={styles.account} numberOfLines={1}>
              {accountLabel}
            </Text>
          </View>
        </View>

        <View style={styles.grid}>
          <View style={styles.gridRow}>
            <DashboardAction
              icon="paw-outline"
              title={t('home.viewPets')}
              support={t('home.petsSupport')}
              href="/pets"
            />
            <DashboardAction
              icon="calendar-outline"
              title={t('home.viewAppointments')}
              support={t('home.appointmentsSupport')}
              href="/appointments"
            />
          </View>
          <View style={styles.gridRow}>
            <DashboardAction
              icon="search-outline"
              title={t('home.viewClinics')}
              support={t('home.clinicsSupport')}
              href="/clinics"
            />
            <DashboardAction
              icon="person-outline"
              title={t('home.viewProfile')}
              support={t('home.profileSupport')}
              href="/profile"
            />
          </View>
          {showProfessionalEntry ? (
            <View style={styles.gridRow}>
              <DashboardAction
                icon="briefcase-outline"
                title={t('home.viewProfessional')}
                support={t('home.professionalSupport')}
                href="/professional"
              />
            </View>
          ) : null}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

type DashboardActionProps = {
  icon: ComponentProps<typeof Ionicons>['name'];
  title: string;
  support: string;
  href: Href;
};

/** One dashboard destination tile. Local: only this screen has a dashboard. */
function DashboardAction({ icon, title, support, href }: DashboardActionProps) {
  return (
    <Pressable
      onPress={() => router.push(href)}
      accessibilityRole="button"
      accessibilityLabel={`${title}. ${support}`}
      style={({ pressed }) => [styles.tile, pressed && styles.tilePressed]}
    >
      <View
        style={styles.tileIcon}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Ionicons name={icon} size={22} color={colors.primary} />
      </View>
      <Text style={styles.tileTitle}>{title}</Text>
      <Text style={styles.tileSupport}>{support}</Text>
    </Pressable>
  );
}

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
  greetingBlock: {
    gap: spacing.xs,
  },
  greeting: {
    ...typography.h1,
    color: colors.textPrimary,
  },
  support: {
    ...typography.body,
    color: colors.textSecondary,
  },
  accountRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.xs,
    marginTop: spacing.sm,
  },
  account: {
    ...typography.caption,
    color: colors.textSecondary,
    flexShrink: 1,
  },
  grid: {
    gap: spacing.md,
  },
  gridRow: {
    flexDirection: 'row',
    gap: spacing.md,
  },
  tile: {
    flex: 1,
    gap: spacing.xs,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: radius.medium,
    padding: spacing.lg,
  },
  tilePressed: {
    backgroundColor: colors.surfaceSoft,
  },
  tileIcon: {
    width: 40,
    height: 40,
    borderRadius: radius.pill,
    backgroundColor: colors.primarySoft,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.sm,
  },
  tileTitle: {
    ...typography.bodyStrong,
    color: colors.textPrimary,
  },
  tileSupport: {
    ...typography.caption,
    color: colors.textSecondary,
  },
});

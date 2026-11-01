import { router } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { ScrollView, StyleSheet } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { BrandMark } from '@/components/design-system/brand-mark';
import {
  OrganizationInvitationContent,
  type OrganizationInvitationActions,
} from '@/components/organization-invitation-content';
import { useOrganizationInvitationFlow } from '@/hooks/use-organization-invitation-flow';
import { invitationExitHref } from '@/lib/organization-invitation-flow';
import { useSession } from '@/lib/session-provider';
import { colors } from '@/theme/colors';
import { spacing } from '@/theme/spacing';

/**
 * Organization Invitation acceptance (SPEC-ORG-003 §12), reached from the
 * App Link `https://app.menizvet.com/invitations/organization/accept`.
 * Registered unconditionally in the root layout — like reset-password — so it
 * opens signed out, on cold start and while running. The link's reference and
 * secret never arrive as route params: `+native-intent` captures them and
 * rewrites the target to this bare route; the flow moves the proof into the
 * secure store. Signed out, nothing about the Invitation is shown; Sign in and
 * Create account open above this screen, which resumes when a session exists.
 */
export default function OrganizationInvitationAcceptRoute() {
  const { session, user, isLoading, isPasswordRecovery } = useSession();
  const hasSession = session !== null && !isPasswordRecovery;
  const isEmailConfirmed = Boolean(user?.email_confirmed_at);
  const flow = useOrganizationInvitationFlow({
    isSessionLoading: isLoading,
    hasSession,
    userId: hasSession ? (user?.id ?? null) : null,
    isEmailConfirmed,
  });

  const actions: OrganizationInvitationActions = {
    accept: () => void flow.accept(),
    cancelMismatch: flow.cancelMismatch,
    retry: flow.retry,
    reloadAccess: flow.reloadAccess,
    notNow: () => void flow.notNow(),
    signIn: () => router.push('/sign-in'),
    createAccount: () => router.push('/register'),
    close: () => router.replace(invitationExitHref(hasSession)),
    goToProfessional: () => router.replace('/professional'),
  };

  return (
    <SafeAreaView style={styles.safeArea}>
      <StatusBar style="dark" />
      <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
        <BrandMark size={32} />
        <OrganizationInvitationContent
          phase={flow.phase}
          isEmailConfirmed={isEmailConfirmed}
          actions={actions}
        />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flexGrow: 1,
    gap: spacing.xl,
    paddingHorizontal: spacing.screenHorizontal,
    paddingTop: spacing.lg,
    paddingBottom: spacing.xxxl,
  },
});

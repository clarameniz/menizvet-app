import { router } from 'expo-router';
import { useEffect, useRef } from 'react';

import { ORGANIZATION_INVITATION_ROUTE } from '@/lib/organization-invitation-link';
import { isOrganizationInvitationScreenMounted } from '@/lib/organization-invitation-intake';
import { hasPendingOrganizationInvitation } from '@/lib/pending-organization-invitation';
import { useSession } from '@/lib/session-provider';

/**
 * True only for a sign-in after bootstrap: no ordinary session before, one
 * now. Bootstrap with an existing session, sign-out, and password recovery
 * never resume.
 */
export function isSignInTransition(
  previous: boolean | null,
  next: { isSessionLoading: boolean; hasSession: boolean; isPasswordRecovery: boolean },
): boolean {
  return (
    previous === false && !next.isSessionLoading && next.hasSession && !next.isPasswordRecovery
  );
}

/**
 * SPEC-ORG-003 §12 continuation: after a sign-in — including one that follows
 * registration and email confirmation, possibly after the app restarted — a
 * pending Invitation proof in the secure store reopens the acceptance screen
 * without reopening the email. When that screen is still mounted under the
 * sign-in screen it resumes by itself, so nothing is navigated. Never accepts.
 * Mounted once from the root layout.
 */
export function usePendingOrganizationInvitationResume(): void {
  const { session, isLoading, isPasswordRecovery } = useSession();
  const hadSession = useRef<boolean | null>(null);
  const hasSession = session !== null;

  useEffect(() => {
    if (isLoading) return;
    const previous = hadSession.current;
    hadSession.current = hasSession && !isPasswordRecovery;
    if (
      !isSignInTransition(previous, { isSessionLoading: isLoading, hasSession, isPasswordRecovery })
    ) {
      return;
    }

    let isMounted = true;
    void hasPendingOrganizationInvitation().then((pending) => {
      if (!isMounted || !pending || isOrganizationInvitationScreenMounted()) return;
      router.push(ORGANIZATION_INVITATION_ROUTE);
    });
    return () => {
      isMounted = false;
    };
  }, [hasSession, isLoading, isPasswordRecovery]);
}

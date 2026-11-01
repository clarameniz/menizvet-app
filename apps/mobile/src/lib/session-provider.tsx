import type { Session, User } from '@supabase/supabase-js';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from 'react';
import { AppState } from 'react-native';

import { clearPendingOrganizationInvitation } from '@/lib/pending-organization-invitation';
import { disableCurrentPushRegistrations } from '@/lib/push-registration';
import { supabase } from '@/lib/supabase';

type SessionContextValue = {
  session: Session | null;
  user: User | null;
  isLoading: boolean;
  /**
   * True once Supabase has emitted a PASSWORD_RECOVERY auth event (the user
   * followed a password-reset deep link). A recovery session is a real
   * Supabase session, so routes need this flag to distinguish "authenticated
   * because recovering a password" from "authenticated, ordinary use" and
   * keep the user on the reset-password screen instead of the main app.
   */
  isPasswordRecovery: boolean;
  /** Called once the user has successfully set a new password. */
  completePasswordRecovery: () => void;
  /**
   * The single centralized sign-out path for every real production sign-out
   * (Milestone H): best-effort disables this device's current Push
   * Registration, then performs the ordinary Supabase sign-out. Push
   * cleanup is hygiene only — the backend's auth_session_id binding is the
   * real security boundary (SPEC-COM-002 BR-22) — so a cleanup failure must
   * never prevent sign-out.
   */
  signOut: () => Promise<void>;
};

const SessionContext = createContext<SessionContextValue | undefined>(undefined);

export function SessionProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<Session | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [isPasswordRecovery, setIsPasswordRecovery] = useState(false);

  const completePasswordRecovery = useCallback(() => {
    setIsPasswordRecovery(false);
  }, []);

  useEffect(() => {
    let isMounted = true;

    supabase.auth.getSession().then(({ data }) => {
      if (!isMounted) return;
      setSession(data.session);
      setIsLoading(false);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((event, nextSession) => {
      if (!isMounted) return;
      if (event === 'PASSWORD_RECOVERY') {
        setIsPasswordRecovery(true);
      } else if (event === 'SIGNED_OUT') {
        setIsPasswordRecovery(false);
      }
      setSession(nextSession);
      setIsLoading(false);
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
    };
  }, []);

  // Per Supabase's React Native guidance: supabase-js's own refresh timer
  // must be paused while the app is backgrounded (background timers are
  // unreliable/wasteful) and resumed on foreground so a near-expiry token is
  // refreshed promptly. SessionProvider is mounted exactly once for the
  // app's lifetime (from the root layout), so this effect registers the
  // AppState listener exactly once and never duplicates it.
  useEffect(() => {
    const appStateSubscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        supabase.auth.startAutoRefresh();
      } else {
        supabase.auth.stopAutoRefresh();
      }
    });

    return () => {
      appStateSubscription.remove();
    };
  }, []);

  const signOut = useCallback(async () => {
    // Result intentionally ignored: best-effort only, see the doc comment
    // on SessionContextValue.signOut above. disableCurrentPushRegistrations
    // (Milestone H logout-race fix) also accounts for a registration attempt
    // that is still in flight at sign-out time, not just whichever id was
    // already tracked as "current".
    await disableCurrentPushRegistrations();
    // SPEC-ORG-003 §12: a pending Organization Invitation proof never outlives
    // the signed-in session it was being accepted into.
    await clearPendingOrganizationInvitation();
    await supabase.auth.signOut();
  }, []);

  const value = useMemo<SessionContextValue>(
    () => ({
      session,
      user: session?.user ?? null,
      isLoading,
      isPasswordRecovery,
      completePasswordRecovery,
      signOut,
    }),
    [session, isLoading, isPasswordRecovery, completePasswordRecovery, signOut],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession() {
  const context = useContext(SessionContext);
  if (context === undefined) {
    throw new Error('useSession must be used within a SessionProvider');
  }
  return context;
}

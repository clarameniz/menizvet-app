import { createElement, useEffect } from 'react';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';

import { clearPendingOrganizationInvitation } from '@/lib/pending-organization-invitation';
import { disableCurrentPushRegistrations } from '@/lib/push-registration';
import { SessionProvider, useSession } from '@/lib/session-provider';
import { supabase } from '@/lib/supabase';

jest.mock('@/lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: jest.fn(async () => ({ data: { session: null } })),
      onAuthStateChange: jest.fn(() => ({ data: { subscription: { unsubscribe: jest.fn() } } })),
      startAutoRefresh: jest.fn(),
      stopAutoRefresh: jest.fn(),
      signOut: jest.fn(async () => ({ error: null })),
    },
  },
}));
jest.mock('@/lib/push-registration', () => ({ disableCurrentPushRegistrations: jest.fn() }));
jest.mock('@/lib/pending-organization-invitation', () => ({
  clearPendingOrganizationInvitation: jest.fn(async () => undefined),
}));

const captured: { signOut: (() => Promise<void>) | null } = { signOut: null };
function Probe() {
  const { signOut } = useSession();
  useEffect(() => {
    captured.signOut = signOut;
  }, [signOut]);
  return null;
}

describe('centralized sign-out (SPEC-ORG-003 §12)', () => {
  it('clears any pending Organization Invitation proof before signing out', async () => {
    const order: string[] = [];
    (clearPendingOrganizationInvitation as jest.Mock).mockImplementation(async () => {
      order.push('clear');
    });
    (supabase.auth.signOut as jest.Mock).mockImplementation(async () => {
      order.push('signOut');
      return { error: null };
    });
    let tree: ReactTestRenderer;
    await act(async () => {
      tree = create(createElement(SessionProvider, null, createElement(Probe)));
    });

    await act(async () => {
      await captured.signOut?.();
    });

    expect(disableCurrentPushRegistrations).toHaveBeenCalledTimes(1);
    expect(clearPendingOrganizationInvitation).toHaveBeenCalledTimes(1);
    expect(order).toEqual(['clear', 'signOut']);
    await act(async () => tree.unmount());
  });
});

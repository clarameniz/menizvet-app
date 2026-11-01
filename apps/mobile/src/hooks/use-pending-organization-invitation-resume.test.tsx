import { createElement } from 'react';
import { act, create, type ReactTestRenderer } from 'react-test-renderer';
import { router } from 'expo-router';

import {
  isSignInTransition,
  usePendingOrganizationInvitationResume,
} from '@/hooks/use-pending-organization-invitation-resume';
import { registerOrganizationInvitationScreen } from '@/lib/organization-invitation-intake';
import { hasPendingOrganizationInvitation } from '@/lib/pending-organization-invitation';

jest.mock('expo-router', () => ({ router: { push: jest.fn() } }));
jest.mock('@/lib/pending-organization-invitation', () => ({
  hasPendingOrganizationInvitation: jest.fn(),
}));
type MockSession = { session: object | null; isLoading: boolean; isPasswordRecovery: boolean };
let mockSession: MockSession;
jest.mock('@/lib/session-provider', () => ({ useSession: () => mockSession }));

const hasPending = hasPendingOrganizationInvitation as jest.Mock;
const BOOTSTRAPPING: MockSession = { session: null, isLoading: true, isPasswordRecovery: false };
const SIGNED_OUT: MockSession = { session: null, isLoading: false, isPasswordRecovery: false };
const SIGNED_IN: MockSession = { session: {}, isLoading: false, isPasswordRecovery: false };

function Probe() {
  usePendingOrganizationInvitationResume();
  return null;
}
let tree: ReactTestRenderer;
async function show(next: MockSession) {
  mockSession = next;
  await act(async () => {
    if (tree) tree.update(createElement(Probe));
    else tree = create(createElement(Probe));
  });
  await act(async () => {
    await Promise.resolve();
  });
}

beforeEach(() => {
  jest.clearAllMocks();
  hasPending.mockResolvedValue(true);
  tree = undefined as unknown as ReactTestRenderer;
});
afterEach(async () => {
  await act(async () => tree?.unmount());
});

describe('isSignInTransition', () => {
  it('is true only from a resolved signed-out state into an ordinary session', () => {
    const next = { isSessionLoading: false, hasSession: true, isPasswordRecovery: false };
    expect(isSignInTransition(false, next)).toBe(true);
    expect(isSignInTransition(null, next)).toBe(false);
    expect(isSignInTransition(true, next)).toBe(false);
    expect(isSignInTransition(false, { ...next, isPasswordRecovery: true })).toBe(false);
    expect(isSignInTransition(false, { ...next, hasSession: false })).toBe(false);
    expect(isSignInTransition(false, { ...next, isSessionLoading: true })).toBe(false);
  });
});

describe('usePendingOrganizationInvitationResume', () => {
  it('reopens the acceptance screen after sign-in when a proof is pending', async () => {
    await show(BOOTSTRAPPING);
    await show(SIGNED_OUT);
    await show(SIGNED_IN);
    expect(router.push).toHaveBeenCalledWith('/invitations/organization/accept');
    expect(router.push).toHaveBeenCalledTimes(1);
  });

  it('does nothing when the screen is still open under the sign-in screen (it resumes itself)', async () => {
    const unregister = registerOrganizationInvitationScreen();
    await show(SIGNED_OUT);
    await show(SIGNED_IN);
    expect(router.push).not.toHaveBeenCalled();
    unregister();
  });

  it('does nothing without a pending proof', async () => {
    hasPending.mockResolvedValue(false);
    await show(SIGNED_OUT);
    await show(SIGNED_IN);
    expect(router.push).not.toHaveBeenCalled();
  });

  it('never resumes on a cold start that already has a session, or for password recovery', async () => {
    await show(BOOTSTRAPPING);
    await show(SIGNED_IN);
    expect(router.push).not.toHaveBeenCalled();

    await act(async () => tree.unmount());
    tree = undefined as unknown as ReactTestRenderer;
    await show(SIGNED_OUT);
    await show({ ...SIGNED_IN, isPasswordRecovery: true });
    expect(router.push).not.toHaveBeenCalled();
  });
});

import * as Linking from 'expo-linking';

import { redirectSystemPath } from '@/app/+native-intent';
import { takeStagedOrganizationInvitationLink } from '@/lib/organization-invitation-intake';

jest.mock('expo-linking', () => ({ getLinkingURL: jest.fn(), clearInitialURL: jest.fn() }));
const getLinkingURL = Linking.getLinkingURL as jest.Mock;
const clearInitialURL = Linking.clearInitialURL as jest.Mock;

// Synthetic credential only.
const ID = '0e1d2c3b-4a59-4687-9a6b-5c4d3e2f1a0b';
const SECRET = 'U3ludGhldGljLW5vdC1hLXJlYWwtc2VjcmV0';
const LINK = `https://app.menizvet.com/invitations/organization/accept?invitation=${ID}#secret=${SECRET}`;
const ROOT = 'com.menizvet://';

beforeEach(() => {
  jest.clearAllMocks();
  getLinkingURL.mockReturnValue(null);
  takeStagedOrganizationInvitationLink();
});

describe('redirectSystemPath (cold-start intake order)', () => {
  it('captures the Invitation link Expo Router hands over, then clears the native launch cache', () => {
    expect(redirectSystemPath({ path: LINK, initial: true })).toBe(
      '/invitations/organization/accept',
    );
    expect(takeStagedOrganizationInvitationLink()).toEqual({
      kind: 'credential',
      credential: { invitationId: ID, secret: SECRET },
    });
    expect(clearInitialURL).toHaveBeenCalledTimes(1);
  });

  it('recovers the launch link when Expo Router timed out to the root URL on a slow cold start', () => {
    getLinkingURL.mockReturnValue(LINK);

    const target = redirectSystemPath({ path: ROOT, initial: true });

    expect(target).toBe('/invitations/organization/accept');
    expect(target).not.toContain(SECRET);
    expect(takeStagedOrganizationInvitationLink()).toEqual({
      kind: 'credential',
      credential: { invitationId: ID, secret: SECRET },
    });
    expect(clearInitialURL).toHaveBeenCalledTimes(1);
  });

  it('never consults the launch cache for links received while running', () => {
    getLinkingURL.mockReturnValue(LINK);

    expect(redirectSystemPath({ path: ROOT, initial: false })).toBe(ROOT);
    expect(getLinkingURL).not.toHaveBeenCalled();
    expect(takeStagedOrganizationInvitationLink()).toBeNull();
  });

  it('a JavaScript reload after capture does not re-capture the handled link', () => {
    getLinkingURL.mockReturnValueOnce(LINK);
    redirectSystemPath({ path: ROOT, initial: true });
    takeStagedOrganizationInvitationLink();
    // The native cache was cleared, so the next process-level read is empty.
    getLinkingURL.mockReturnValue(null);

    expect(redirectSystemPath({ path: ROOT, initial: true })).toBe(ROOT);
    expect(takeStagedOrganizationInvitationLink()).toBeNull();
  });

  it('leaves an ordinary launch and other App Links untouched', () => {
    const appointment = 'https://app.menizvet.com/appointments/abc?petId=def';
    getLinkingURL.mockReturnValue(appointment);

    expect(redirectSystemPath({ path: ROOT, initial: true })).toBe(ROOT);
    expect(redirectSystemPath({ path: appointment, initial: true })).toBe(appointment);
    expect(clearInitialURL).not.toHaveBeenCalled();
    expect(takeStagedOrganizationInvitationLink()).toBeNull();
  });

  it('survives a failing native linking module', () => {
    getLinkingURL.mockImplementation(() => {
      throw new Error('native module unavailable');
    });
    expect(redirectSystemPath({ path: ROOT, initial: true })).toBe(ROOT);
  });
});

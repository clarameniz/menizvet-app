import { getStateFromPath } from 'expo-router/build/fork/getStateFromPath';

import {
  routeIncomingSystemPath,
  takeStagedOrganizationInvitationLink,
} from '@/lib/organization-invitation-intake';

/**
 * Regression guard on Expo Router's own URL parser (SPEC-ORG-003 §12, Note
 * 33). Expo Router copies a URL fragment into route params as `#`, so the raw
 * Invitation link would put the secret into navigation state. The
 * `+native-intent` rewrite hands the router a bare path instead. If an Expo
 * Router upgrade changes either behaviour, this test says so.
 */
const ID = '3f2b6c1e-9a4d-4c3b-8e2f-1a2b3c4d5e6f';
const SECRET = 'cmVkYWN0ZWQtYnV0LXJlYWxpc3RpYy1zaGFwZWQtc2VjcmV0';
const PATH = `/invitations/organization/accept?invitation=${ID}#secret=${SECRET}`;
const CONFIG = {
  screens: { 'invitations/organization/accept': 'invitations/organization/accept' },
};

afterEach(() => {
  takeStagedOrganizationInvitationLink();
});

describe('Expo Router route params for the Invitation link', () => {
  it('would carry the fragment secret if the raw link reached the router', () => {
    expect(JSON.stringify(getStateFromPath(PATH, CONFIG))).toContain(SECRET);
  });

  it('carries neither the secret nor the reference after the native-intent rewrite', () => {
    const state = getStateFromPath(
      routeIncomingSystemPath(`https://app.menizvet.com${PATH}`),
      CONFIG,
    );

    expect(state?.routes[0]?.name).toBe('invitations/organization/accept');
    expect(JSON.stringify(state)).not.toContain(SECRET);
    expect(JSON.stringify(state)).not.toContain(ID);
  });
});

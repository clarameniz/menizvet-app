import {
  getOrganizationInvitationIntakeVersion,
  isOrganizationInvitationScreenMounted,
  registerOrganizationInvitationScreen,
  routeIncomingSystemPath,
  subscribeOrganizationInvitationIntake,
  takeStagedOrganizationInvitationLink,
} from '@/lib/organization-invitation-intake';

const ID = '3f2b6c1e-9a4d-4c3b-8e2f-1a2b3c4d5e6f';
const SECRET = 'cmVkYWN0ZWQtYnV0LXJlYWxpc3RpYy1zaGFwZWQtc2VjcmV0';
const LINK = `https://app.menizvet.com/invitations/organization/accept?invitation=${ID}#secret=${SECRET}`;

afterEach(() => {
  takeStagedOrganizationInvitationLink();
});

describe('routeIncomingSystemPath (Expo Router redirectSystemPath)', () => {
  it('rewrites an Invitation link to the bare route: no query, no fragment, no secret', () => {
    const target = routeIncomingSystemPath(LINK);

    expect(target).toBe('/invitations/organization/accept');
    expect(target).not.toContain('#');
    expect(target).not.toContain('?');
    expect(target).not.toContain(SECRET);
    expect(target).not.toContain(ID);
  });

  it('stages the captured proof exactly once for the screen', () => {
    routeIncomingSystemPath(LINK);

    expect(takeStagedOrganizationInvitationLink()).toEqual({
      kind: 'credential',
      credential: { invitationId: ID, secret: SECRET },
    });
    expect(takeStagedOrganizationInvitationLink()).toBeNull();
  });

  it('routes an invalid Invitation link to the screen without staging any secret', () => {
    expect(routeIncomingSystemPath(`/invitations/organization/accept?invitation=${ID}`)).toBe(
      '/invitations/organization/accept',
    );
    expect(takeStagedOrganizationInvitationLink()).toEqual({ kind: 'invalid' });
  });

  it('passes every other URL through untouched and stages nothing', () => {
    const appointment = 'https://app.menizvet.com/appointments/abc?petId=def';
    const version = getOrganizationInvitationIntakeVersion();

    expect(routeIncomingSystemPath(appointment)).toBe(appointment);
    expect(takeStagedOrganizationInvitationLink()).toBeNull();
    expect(getOrganizationInvitationIntakeVersion()).toBe(version);
  });

  it('notifies an open screen that a newer link arrived (warm start)', () => {
    const listener = jest.fn();
    const unsubscribe = subscribeOrganizationInvitationIntake(listener);
    const version = getOrganizationInvitationIntakeVersion();

    routeIncomingSystemPath(LINK);

    expect(listener).toHaveBeenCalledTimes(1);
    expect(getOrganizationInvitationIntakeVersion()).toBe(version + 1);
    unsubscribe();
    routeIncomingSystemPath(LINK);
    expect(listener).toHaveBeenCalledTimes(1);
  });
});

describe('acceptance screen registration', () => {
  it('tracks whether the acceptance screen is mounted', () => {
    expect(isOrganizationInvitationScreenMounted()).toBe(false);
    const unregister = registerOrganizationInvitationScreen();
    expect(isOrganizationInvitationScreenMounted()).toBe(true);
    unregister();
    expect(isOrganizationInvitationScreenMounted()).toBe(false);
  });
});

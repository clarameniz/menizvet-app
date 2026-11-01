import {
  ORGANIZATION_INVITATION_ROUTE,
  parseOrganizationInvitationLink,
} from '@/lib/organization-invitation-link';

const ID = '3f2b6c1e-9a4d-4c3b-8e2f-1a2b3c4d5e6f';
// Shape of a real B1 secret: base64url of 32 random bytes, no padding.
const SECRET = 'Zk9yQ2FybG9zLW9ubHktYmFzZTY0dXJsLXNlY3JldF8x';
const LINK = `https://app.menizvet.com/invitations/organization/accept?invitation=${ID}#secret=${SECRET}`;

describe('parseOrganizationInvitationLink', () => {
  it('extracts the reference from the query and the secret from the fragment (cold start URL)', () => {
    expect(parseOrganizationInvitationLink(LINK)).toEqual({
      kind: 'credential',
      credential: { invitationId: ID, secret: SECRET },
    });
  });

  it('accepts the same link delivered while running, a trailing slash, an uppercase id and :443', () => {
    expect(
      parseOrganizationInvitationLink(
        `HTTPS://APP.MENIZVET.COM:443/invitations/organization/accept/?invitation=${ID.toUpperCase()}#secret=${SECRET}`,
      ),
    ).toEqual({ kind: 'credential', credential: { invitationId: ID, secret: SECRET } });
  });

  it('accepts a router path that still carries the query and fragment', () => {
    expect(
      parseOrganizationInvitationLink(
        `/invitations/organization/accept?invitation=${ID}#secret=${SECRET}`,
      ),
    ).toEqual({ kind: 'credential', credential: { invitationId: ID, secret: SECRET } });
  });

  it('decodes percent-encoding before validating', () => {
    expect(
      parseOrganizationInvitationLink(
        `https://app.menizvet.com/invitations/organization/accept?invitation=${ID}#secret=${encodeURIComponent(SECRET)}`,
      ),
    ).toEqual({ kind: 'credential', credential: { invitationId: ID, secret: SECRET } });
  });

  it.each([
    ['malformed UUID', `${ORGANIZATION_INVITATION_ROUTE}?invitation=not-a-uuid#secret=${SECRET}`],
    ['missing reference', `${ORGANIZATION_INVITATION_ROUTE}#secret=${SECRET}`],
    [
      'repeated reference',
      `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}&invitation=${ID}#secret=${SECRET}`,
    ],
    ['missing secret', `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}`],
    ['empty secret', `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}#secret=`],
    ['wrong fragment key', `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}#token=${SECRET}`],
    [
      'extra fragment member',
      `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}#secret=${SECRET}&x=1`,
    ],
    ['secret in the query', `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}&secret=${SECRET}`],
    [
      'secret in query and fragment',
      `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}&secret=a#secret=${SECRET}`,
    ],
    ['non-base64url secret', `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}#secret=abc%2Bdef`],
    [
      'oversized secret',
      `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}#secret=${'a'.repeat(513)}`,
    ],
    ['broken escape', `${ORGANIZATION_INVITATION_ROUTE}?invitation=${ID}#secret=%E0%A4%A`],
  ])('treats %s as an invalid Invitation link', (_label, url) => {
    expect(parseOrganizationInvitationLink(url)).toEqual({ kind: 'invalid' });
  });

  it.each([
    'https://app.menizvet.com/appointments/abc?petId=def',
    'https://app.menizvet.com/invitations/guardianship/accept?invitation=x#secret=y',
    `https://evil.example/invitations/organization/accept?invitation=${ID}#secret=${SECRET}`,
    `http://app.menizvet.com/invitations/organization/accept?invitation=${ID}#secret=${SECRET}`,
    `com.menizvet://reset-password?code=abc`,
    '/professional',
    '',
  ])('leaves other URLs to the router: %s', (url) => {
    expect(parseOrganizationInvitationLink(url)).toBeNull();
  });

  it('never throws on hostile input', () => {
    expect(() => parseOrganizationInvitationLink('%%%#%%%?%%%')).not.toThrow();
    expect(parseOrganizationInvitationLink(undefined as unknown as string)).toBeNull();
  });
});

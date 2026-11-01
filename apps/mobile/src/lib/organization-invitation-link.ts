/**
 * Organization Invitation email link (SPEC-ORG-003 §12):
 *
 *   https://app.menizvet.com/invitations/organization/accept?invitation=<id>#secret=<secret>
 *
 * The secret travels only in the fragment, which browsers never send to the
 * web origin. This module recognizes that link and extracts the pending proof
 * from the full incoming URL. It is pure string parsing on purpose: it runs in
 * Expo Router's `+native-intent` hook before any route (and before any URL
 * polyfill is guaranteed to be loaded), and it never throws.
 *
 * Shape validation only (UUID reference; non-empty base64url secret). The
 * secret proves nothing on the client; the backend verifies it.
 */

export const ORGANIZATION_INVITATION_ROUTE = '/invitations/organization/accept';

export type OrganizationInvitationCredential = {
  invitationId: string;
  secret: string;
};

export type OrganizationInvitationLink =
  { kind: 'credential'; credential: OrganizationInvitationCredential } | { kind: 'invalid' };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** base64url without padding; bounded so a hostile link cannot grow storage. */
const SECRET = /^[A-Za-z0-9_-]{1,512}$/;
const APP_LINK_ORIGIN = /^https:\/\/app\.menizvet\.com(?::443)?(?=\/|$)/i;

export function isInvitationId(value: unknown): value is string {
  return typeof value === 'string' && UUID.test(value);
}

export function isInvitationSecret(value: unknown): value is string {
  return typeof value === 'string' && SECRET.test(value);
}

function decode(component: string): string | null {
  try {
    return decodeURIComponent(component.replace(/\+/g, ' '));
  } catch {
    return null;
  }
}

/** `null` for a malformed component; repeated keys keep every value. */
function parseParameters(raw: string): Map<string, string[]> | null {
  const parameters = new Map<string, string[]>();
  if (raw === '') return parameters;
  for (const pair of raw.split('&')) {
    if (pair === '') continue;
    const separator = pair.indexOf('=');
    const key = decode(separator === -1 ? pair : pair.slice(0, separator));
    const value = decode(separator === -1 ? '' : pair.slice(separator + 1));
    if (key === null || value === null) return null;
    parameters.set(key, [...(parameters.get(key) ?? []), value]);
  }
  return parameters;
}

function single(parameters: Map<string, string[]>, key: string): string | null {
  const values = parameters.get(key);
  return values?.length === 1 ? values[0] : null;
}

/**
 * `null` when `url` is not an Organization Invitation acceptance link at all
 * (every other URL is left to the router untouched). An acceptance link whose
 * reference or secret is missing or malformed is `invalid`: it is shown as
 * unavailable and nothing from it is stored.
 */
export function parseOrganizationInvitationLink(url: string): OrganizationInvitationLink | null {
  if (typeof url !== 'string') return null;

  const fragmentStart = url.indexOf('#');
  const beforeFragment = fragmentStart === -1 ? url : url.slice(0, fragmentStart);
  const fragment = fragmentStart === -1 ? '' : url.slice(fragmentStart + 1);
  const queryStart = beforeFragment.indexOf('?');
  const location = queryStart === -1 ? beforeFragment : beforeFragment.slice(0, queryStart);
  const query = queryStart === -1 ? '' : beforeFragment.slice(queryStart + 1);

  let path: string;
  if (APP_LINK_ORIGIN.test(location)) {
    path = location.replace(APP_LINK_ORIGIN, '') || '/';
  } else if (location.startsWith('/')) {
    path = location;
  } else {
    return null;
  }
  if (path.replace(/\/+$/, '').toLowerCase() !== ORGANIZATION_INVITATION_ROUTE) return null;

  const queryParameters = parseParameters(query);
  const fragmentParameters = parseParameters(fragment);
  if (queryParameters === null || fragmentParameters === null) return { kind: 'invalid' };

  // A secret that travelled in the query already reached a server; never
  // accept it, and accept nothing but the secret in the fragment.
  if (queryParameters.has('secret')) return { kind: 'invalid' };
  if (fragmentParameters.size !== 1) return { kind: 'invalid' };

  const invitationId = single(queryParameters, 'invitation');
  const secret = single(fragmentParameters, 'secret');
  if (!isInvitationId(invitationId) || !isInvitationSecret(secret)) return { kind: 'invalid' };

  return {
    kind: 'credential',
    credential: { invitationId: invitationId.toLowerCase(), secret },
  };
}

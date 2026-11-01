import type { TranslationKey } from '@/i18n/i18n';

/**
 * Pure presentation helpers for the Appointment requester contact
 * (SPEC-APT-012 BR-49/BR-50, SPEC-ID-006 BR-42): the original requester, not
 * necessarily a current Guardian. No identifier is ever rendered.
 */

type Translate = (key: TranslationKey, options?: Record<string, string | number>) => string;

/** "Requested by …" for a schedule row, or a neutral fallback without a name. */
export function requesterLine(displayName: string | null, t: Translate): string {
  return displayName === null
    ? t('appointmentContact.requestedByUnnamed')
    : t('appointmentContact.requestedBy', { name: displayName });
}

/** The requester's name, or a neutral fallback, for the detail's contact section. */
export function requesterName(displayName: string | null, t: Translate): string {
  return displayName ?? t('appointmentContact.unnamed');
}

// One plain address: no whitespace or control characters, exactly one "@", and
// none of the characters that would add mailto headers, recipients, or a
// fragment (?, &, #, %, comma, semicolon) or break out of the URL.
const SAFE_ADDRESS =
  /^[^\s@?&#%,;:<>"'\\/()[\]\u0000-\u001f\u007f]+@[^\s@?&#%,;:<>"'\\/()[\]\u0000-\u001f\u007f]+\.[^\s@?&#%,;:<>"'\\/()[\]\u0000-\u001f\u007f]+$/;

/**
 * The `mailto:` URL that opens the device's email application to exactly this
 * address with nothing prefilled, or `null` when there is no address or it is
 * not a plain one (then no action is offered).
 */
export function requesterMailtoUrl(email: string | null): string | null {
  if (email === null || !SAFE_ADDRESS.test(email)) return null;
  return `mailto:${email}`;
}

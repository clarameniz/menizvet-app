import { Linking } from 'react-native';

/**
 * Public MenizVet legal/account pages, opened in the system browser. These
 * are static web pages maintained outside this repository; the app only
 * links to them and implements no account-deletion or data-export behavior
 * itself (no approved Specification defines either — see SPEC-ID-004 §6,
 * SPEC-ID-006 §13 and REQ-NFR-016).
 */
export const PRIVACY_POLICY_URL = 'https://menizvet.com/privacy';
export const DELETE_ACCOUNT_URL = 'https://menizvet.com/delete-account';

/**
 * Opens an external URL through React Native's built-in `Linking` (no extra
 * dependency, no native change). `canOpenURL` is deliberately not used: on
 * Android 11+ it can report `false` for https without a manifest `<queries>`
 * entry even when a browser exists, whereas `openURL` itself rejects when
 * nothing can handle the URL. Failure is returned as `false` rather than
 * thrown, so the caller can show a localized product message; the provider
 * error is never logged or surfaced.
 */
export async function openExternalUrl(url: string): Promise<boolean> {
  try {
    await Linking.openURL(url);
    return true;
  } catch {
    return false;
  }
}

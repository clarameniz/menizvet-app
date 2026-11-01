import { router, type Href } from 'expo-router';

/**
 * The app's single "safe back" rule, shared by every visible back control
 * that should behave exactly like Android hardware back: pop to whatever is
 * really beneath (never stacking a second copy of it), and `replace` to
 * `fallback` only when there is nothing to pop — e.g. the route was opened
 * directly from a deep link or notification.
 *
 * Screens that must return to a specific screen rather than whatever is
 * beneath (Pet detail and Edit Pet success, Appointments — all via
 * `dismissTo`) do not use this.
 */
export function goBackOr(fallback: Href): void {
  if (router.canGoBack()) {
    router.back();
  } else {
    router.replace(fallback);
  }
}

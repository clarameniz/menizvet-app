import { router, type Href } from 'expo-router';

/**
 * Pets stack return paths. Both use `router.dismissTo`, the same pattern as
 * Appointments (see appointments-navigation.ts / appointments/[id].tsx): if
 * the target screen is already beneath in the stack, it pops back to that
 * same instance — which re-reads on focus, so it is never shown stale — and
 * no duplicate is left behind; if it isn't (direct / deep-link entry), the
 * current screen is replaced with the target, so there is always a safe
 * destination.
 */

export const PETS_LIST_HREF: Href = '/pets';

export function petDetailHref(petId: string): Href {
  return `/pets/${encodeURIComponent(petId)}`;
}

/** Pet detail → My Pets, without stacking a second My Pets. */
export function returnToPetsList(): void {
  router.dismissTo(PETS_LIST_HREF);
}

/** Edit Pet (after a successful save) → that Pet's detail, without a duplicate detail. */
export function returnToPetDetail(petId: string): void {
  router.dismissTo(petDetailHref(petId));
}

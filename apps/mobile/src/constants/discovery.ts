/**
 * Phase-1 Discovery configuration (Mobile Milestone E). Single source of
 * truth for values the backend deliberately leaves as product/architecture
 * configuration rather than a domain invariant — see SPEC-DIS-002 §5 and
 * docs/DISCOVERY_BACKEND.md. Never confuse NEARBY_SEARCH_RADIUS_METERS with
 * discover_nearby_clinics' own purely mathematical great-circle ceiling
 * (pi() * mean Earth radius): that ceiling is a server-side validation bound
 * the client never touches or displays, not a product tier.
 */
export const NEARBY_SEARCH_RADIUS_METERS = 10_000;

export const BASIC_DISCOVERY_PAGE_SIZE = 20;
export const NEARBY_DISCOVERY_PAGE_SIZE = 20;

/** Matches discover_clinics_in_viewport's own server-side page cap. */
export const VIEWPORT_DISCOVERY_PAGE_SIZE = 100;

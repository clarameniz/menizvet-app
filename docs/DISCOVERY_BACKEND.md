# Discovery Backend Operations

This document defines the deployed backend API contract for public Clinic
Discovery. Product and business rules remain governed by
[`SPEC-DIS-001`](../specs/discovery/SPEC-DIS-001-discover-published-clinics.md),
[`SPEC-DIS-002`](../specs/discovery/SPEC-DIS-002-discover-nearby-clinics.md),
and [`SPEC-DIS-003`](../specs/discovery/SPEC-DIS-003-view-clinics-on-map.md).
This document does not restate or reinterpret those Specifications; it
records the physical read contract that satisfies them.

## Repository boundary

This repository owns three plain `SECURITY DEFINER` PostgreSQL read
functions, layered over the existing `clinics`, `clinic_locations`, and
`clinic_public_profiles` tables established in earlier Slices, plus the
`SPEC-DIS-004` name-search read described below. Discovery
introduces no Edge Function, no external provider, no scheduled job, and no
new persisted entity. All three functions are `STABLE`, run with an empty
`search_path`, and are executable by both `anon` and `authenticated` — no
authentication is required, and an authenticated caller receives no
additional information.

## Public read contract

All three are ordinary PostgreSQL functions (RPC), not HTTP endpoints.

### `get_published_clinic_location(p_clinic_id uuid)`

Returns at most one row: `clinic_id`, `address_text`, `latitude`,
`longitude`. A nonexistent Clinic id and a currently unpublished Clinic both
return zero rows, with no distinguishing behavior — Discovery cannot be used
to probe for the existence of an unpublished Clinic.

### `discover_nearby_clinics(p_latitude, p_longitude, p_radius_meters, p_limit default 50, p_after_distance_meters default null, p_after_clinic_id default null)`

Returns a `jsonb` envelope:

```json
{
  "clinics": [
    {
      "clinic_id": "...", "display_name": "...", "description": "...",
      "public_phone": "...", "public_email": "...", "website": "...",
      "address_text": "...", "latitude": 0.0, "longitude": 0.0,
      "distance_meters": 0.0
    }
  ],
  "has_more": false,
  "next_after_distance_meters": null,
  "next_after_clinic_id": null
}
```

`p_radius_meters` is a required caller input; no default is defined by this
repository. The only enforced upper bound is a technical/mathematical one —
the greatest possible great-circle distance between two terrestrial points
under the sphere model used (`pi()` times the mean Earth radius) — not a
product-defined search-radius tier. Results are ordered nearest-first
(`distance_meters` ascending, `clinic_id` ascending as a deterministic
tie-breaker), page size defaults to 50 and is capped at 100 regardless of
the requested `p_limit`, and `next_after_distance_meters` /
`next_after_clinic_id` always reflect the final row actually returned on
the page, never a discarded probe row.

### `discover_clinics_in_viewport(p_min_latitude, p_max_latitude, p_min_longitude, p_max_longitude, p_limit default 100, p_after_clinic_id default null)`

Returns a `jsonb` envelope shaped like the above, without `distance_meters`,
ordered by `clinic_id` ascending. Bounds are inclusive. Page size defaults
to and is capped at 100. A viewport whose longitude span crosses the
antimeridian (`min_longitude` greater than `max_longitude`) is rejected;
this is a documented Phase 1 API limitation, not wrap-around global-map
behavior. A caller whose visible map area crosses ±180° longitude must
issue two non-crossing viewport queries.

### `discover_published_clinics(p_search default null, p_after_display_name default null, p_after_clinic_id default null, p_limit default 20)`

Defined by [`SPEC-DIS-004`](../specs/discovery/SPEC-DIS-004-search-published-clinics-by-name.md)
(migration `20261120090000_published_clinic_name_search.sql`). **Status:
applied to DEVELOPMENT (`eqvlydfflfvltprkwcxx`) and verified there with the
read-only checks `supabase/provisioning/dis004_dev_clinic_name_search_preflight_readonly.sql`
/ `dis004_dev_clinic_name_search_postdeploy_readonly.sql`; not deployed to
Production.**

Returns a `jsonb` envelope:

```json
{
  "clinics": [
    { "clinic_id": "...", "display_name": "...", "description": "...", "address_text": "... or null" }
  ],
  "has_more": false,
  "next_after_display_name": null,
  "next_after_clinic_id": null
}
```

Rows are exactly the Clinics of `published_clinic_public_profiles` (published,
with a public profile), in display-name order (database default collation,
unnamed last, then `clinic_id`), optionally narrowed by a literal substring of
the normalized display name. `address_text` follows exactly the
`get_published_clinic_location` rule and is `null` for a Clinic without a
Location, which is still returned. One probe row decides `has_more`; the next
cursor is the last returned row's `(display_name, clinic_id)`. `p_limit` must be
1–50 and `p_search` at most 100 characters, and a name cursor needs its id;
otherwise `22023 Published Clinics page is invalid` (never silently capped).
The read does not consult the caller, writes nothing, and reads every row in
one statement. Its normalization helper `clinic_display_name_search_key(text)`
is executable by no client role and is independent of the professional
`professional_clinic_search_key`.

## Scope and exclusions

- Publication eligibility for every Discovery read is controlled solely by
  `clinics.is_published`; no second discoverability flag exists.
- Appointment/Availability-time Discovery is out of scope: no function
  reads any Availability or Appointment table, and a published Clinic
  remains discoverable with zero configured availability.
- Service/specialty filtering is out of scope (`Later` delivery).
- No Subscription or professional Entitlement gates any Discovery read or
  Clinic publication.
- No new persisted Discovery entity, denormalized search document, or
  cache was introduced; every result is a bounded, non-authoritative
  projection over existing Clinic state.
- No PostGIS, `earthdistance`/`cube`, or other geospatial extension is
  installed; distance uses a plain-SQL Haversine calculation. No new
  index was introduced — existing indexes already narrow every query to
  the published-Clinic set before any geographic computation runs.

## ACL

`clinics`, `clinic_locations`, and `clinic_public_profiles` remain exactly
as private as before this Slice: Row Level Security stays enabled, and
direct `SELECT`/`INSERT`/`UPDATE`/`DELETE` remains denied to `anon` and
`authenticated`. The three functions above are the only path either role
has to any of that content, and each hard-codes the `is_published = true`
predicate rather than trusting a caller-supplied filter.

## Slice 15 closure validation

Slice 15 is closed.

Deterministic closure: a clean isolated database reconstructed from all
source-controlled migrations through `20260905090000_discovery_query_support.sql`
applied successfully, and the rollback-only
`supabase/tests/discovery_slice15.sql` suite passed with zero retained
rows. That suite covers published/unpublished/nonexistent/no-location
lookup behavior, anon/authenticated callable parity, radius boundary
inclusion and outside-radius exclusion using the function's own reported
distance (never hand-computed), near-antipodal Haversine numerical safety,
the great-circle radius bound, deterministic equal-distance tie ordering,
real keyset-cursor round-trips (extracted from actual JSON responses, never
fabricated) for both Nearby and viewport pagination, an oversized
101-Clinic fixture proving the 100-row server-side page cap with no
duplicate or gap, invalid/null/non-finite input rejection, antimeridian
rejection, and the ACL/RLS regression matrix. The Slice 13 and Slice 14
regression suites both passed unchanged against the Slice-15-extended
schema.

### Distance-cursor precision correction

Initial validation surfaced a genuine defect: an unrounded Haversine
`distance_meters` value, once round-tripped through a JSON response and
back (exactly what any real caller does to continue Nearby pagination),
could lose enough precision to make the freshly recomputed distance for a
page's final Clinic compare as strictly greater than its own (very
slightly smaller, reparsed) cursor value — reintroducing that Clinic,
duplicated, on the next page. The fix rounds `distance_meters` to
millimeter precision at the single point where it is computed, before that
value is used for radius filtering, ordering, cursor comparison, or the
returned JSON — with no product-visible effect on "nearby" distance.

### Remote deployment verification

Remote deployment verification confirmed: all three functions exist with
the expected signatures and `SECURITY DEFINER` / `STABLE` / empty-
`search_path` attributes; all expected `EXECUTE` grants for `anon` and
`authenticated` are present; direct `SELECT` on `clinics`,
`clinic_locations`, and `clinic_public_profiles` remains denied to both
roles; a nonexistent published-location lookup returns zero rows without
error; and both Nearby and viewport Discovery return a valid bounded JSON
envelope.

Discovery is a pure database read/query Slice with no Edge Function,
provider, or scheduler component, so no live-provider validation applies
and none was performed.

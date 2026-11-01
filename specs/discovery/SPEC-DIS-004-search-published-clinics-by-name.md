# SPEC-DIS-004 — Search Published Clinics by Name

**Status:** APPROVED
**Requirements:** REQ-DIS-006, REQ-DIS-001
**Domain:** Discovery
**Priority:** P1
**Decision:** product approval 2026-10-26 (contract, separate normalization helper, limit 1–50 rejected otherwise, pages kept on return from a Clinic)

## 1. Intent

Allow Anonymous Visitors and registered Users to browse the published Clinics
in alphabetical order, page by page, and to narrow them by Clinic name.

This Specification defines the text search, ordering, and pagination that
`SPEC-DIS-001` §9 leaves out of scope, for the Clinic list only. Which Clinics
may be discovered, and which information is public, remain defined by
`SPEC-DIS-001` and `SPEC-CLI-004`. Nearby (`SPEC-DIS-002`) and Map
(`SPEC-DIS-003`) Discovery are unchanged.

Authentication is not required.

---

## 2. Preconditions

* Zero or more published Clinics exist.
* A published Clinic may or may not have a current Location.

Authentication is not required.

---

## 3. Business Rules

### BR-1 — Eligibility is exactly `SPEC-DIS-001`

A Clinic can be returned if and only if it participates in public Discovery
under `SPEC-DIS-001`: it is currently published and has its public profile.
This is the same set the Clinic list shows today.

The search, ordering, and pagination of this Specification only narrow,
order, and cut that set. They never widen it.

A nonexistent Clinic and an unpublished Clinic are indistinguishable: neither
is ever returned, and no input reveals whether either exists.

---

### BR-2 — Same result for every caller

The read is available to Anonymous Visitors and to authenticated Users, and
returns the same rows for the same input and the same state, whoever calls it
(`SPEC-DIS-001` BR-1, BR-15).

The read does not consult the caller's identity, Pets, Guardianships,
Organization Memberships, professional context, capabilities, Subscription, or
Entitlements. Public Discovery depends on no professional authorization.

---

### BR-3 — A Location is not required

A published Clinic without a current Location is returned like any other,
with no address (`SPEC-DIS-001` BR-4 and §5; `SPEC-CLI-002`).

The Location never decides whether a Clinic is returned, where it is ordered,
or whether it matches a search.

---

### BR-4 — Returned information

Each returned Clinic carries only:

* `clinic_id` — its identity, to open its public profile (`SPEC-DIS-001` §5);
* `display_name` — its public display name (`SPEC-CLI-004`);
* `description` — its public description, or `null`;
* `address_text` — the public address of its current Location, or `null`
  when it has none.

The address is exposed under exactly the public-visibility rule of
`get_published_clinic_location` (`docs/DISCOVERY_BACKEND.md`): the Clinic is
published and has a current Location. It is never taken from any other source.

No coordinates, contact details, services, opening hours, Appointment
availability, imagery, Organization information, staff, or count are returned.
Contact details stay on the Clinic's public profile.

Each Clinic appears at most once in a page and is never repeated because of
its Location or profile data.

---

### BR-5 — Name search

`p_search` narrows the BR-1 Clinics by public display name. The narrowing is
applied before ordering and before the page is cut, never to a page that was
already cut.

**Search normalization.** `N(text)` is computed, in this order, by:

1. Unicode compatibility decomposition (NFKD);
2. removing every combining mark in U+0300–U+036F;
3. the Unicode root-locale (`und`) lowercase mapping, applied with one fixed
   collation chosen by the read. It must not depend on the database's default
   collation or locale, or on the collation of the value passed in;
4. replacing every run of whitespace with one space (U+0020). Whitespace
   includes space, tab, line breaks, no-break space (U+00A0), and the Unicode
   space separators;
5. removing leading and trailing spaces.

This is the same normalization as `SPEC-ORG-008` BR-22. It is stated here
because the public contract must not change when the professional one does.

**Matching.**

* When `p_search` is `null`, or `N(p_search)` is empty, there is no
  narrowing.
* Otherwise a Clinic matches if and only if it has a display name and
  `N(p_search)` occurs as a contiguous substring of `N(display name)`.
* Matching is literal. No character of the search (`%`, `_`, `\`, `[`, `*`,
  quotes, …) has wildcard or pattern meaning.
* Only the display name is searched. Description, address, services, and
  Organization are not.

Examples:

| Search | Matches the display name |
|---|---|
| `clinica`, `Clínica`, `CLÍNICA` | `Clínica Centro` |
| `pena`, `peña` | `Peña` and `Pena` |
| `veterinaria   peña` | `Clínica Veterinaria Peña` |
| `%`, `_` | only names containing that character |

The accepted limits of `SPEC-ORG-008` BR-22 apply equally (`ß`, `ø`, `œ`, `æ`,
`ł` are not folded to ASCII; combining marks outside U+0300–U+036F are kept;
zero-width characters are not whitespace).

`N` is derived at read time. No normalized value, search term, or index entry
is persisted, and this Specification requires no database extension.

---

### BR-6 — Alphabetical order

Rows are ordered by:

1. public display name, in the database's default collation, with Clinics
   without a display name last;
2. `clinic_id`.

This is one total order: Clinics with identical display names are told apart
only by `clinic_id` (`SPEC-DIS-001` §6, duplicate display names). The search
only removes rows; it never changes their relative order.

A published Clinic always keeps a display name (`SPEC-CLI-004` BR-17). The
placement of Clinics without one exists only so the order stays total.

---

### BR-7 — Keyset pagination

Pages are cut by a keyset cursor, never by an offset.

* The page size is 20 by default; a caller may request 1 to 50.
* The cursor is the complete `(display_name, clinic_id)` of the previous
  page's last row, exactly as returned. The first page has no cursor.
* A later page holds the next matching rows strictly after the cursor, in the
  BR-6 order, using exactly the same key — the same expressions, collation,
  null placement, and tie-breaker. The cursor never uses a normalized value.
* `has_more` is `true` if and only if at least one further matching row
  existed when the page was read.
* No total count is returned.

A cursor is only a position in the order. It is never evidence that a Clinic
exists or is published: a cursor naming an unknown or unpublished Clinic
returns only eligible rows and reveals nothing.

---

### BR-8 — Consistency between pages

Each call observes one snapshot. Between calls, state may change:

* a Clinic unpublished, or renamed so it no longer matches, is not returned by
  later pages (`SPEC-DIS-001` BR-11);
* a rename may move a Clinic across the cursor, so remaining pages may miss it
  or return it again. This is accepted. The client never shows a Clinic twice
  (BR-12), and a new first read is authoritative;
* a newly published Clinic that sorts before the cursor appears only on a new
  first read.

A cursor belongs to the search that produced it. When the search changes the
client discards the cursor and restarts from the first page. The read does not
bind a cursor to a search; whatever cursor is sent, it returns only eligible
rows matching the search of that call.

---

### BR-9 — Read only

The read writes nothing, takes no lock, creates no audit event, and persists
no search term, cursor, result, or normalized value. It grants no access of
any kind (`SPEC-DIS-001` BR-14).

---

## 4. Read Contract

    discover_published_clinics(
        p_search             text    default null,
        p_after_display_name text    default null,
        p_after_clinic_id    uuid    default null,
        p_limit              integer default 20
    ) returns jsonb

Envelope, following the existing Discovery reads (`docs/DISCOVERY_BACKEND.md`):

```json
{
  "clinics": [
    {
      "clinic_id": "...",
      "display_name": "...",
      "description": "... or null",
      "address_text": "... or null"
    }
  ],
  "has_more": false,
  "next_after_display_name": null,
  "next_after_clinic_id": null
}
```

* `next_after_display_name` / `next_after_clinic_id` are the last returned
  row's `display_name` and `clinic_id`, never those of a discarded probe row.
  Both are `null` when the page is empty. `next_after_display_name` is also
  `null` when that row had no display name.
* An empty `clinics` array is a valid result, not an error (`SPEC-DIS-001`
  §6).

**Input validation** — fails with `22023` `Published Clinics page is invalid`
before any Clinic is read when:

* `p_limit` is `null` or outside 1–50 (an out-of-range limit is rejected,
  never silently capped);
* `p_after_display_name` is not `null` while `p_after_clinic_id` is `null`;
* `p_search` is longer than 100 characters, as received.

Validation never depends on stored data. The read raises no other domain
error.

**Security boundary.**

* `SECURITY DEFINER`, `STABLE`, empty `search_path`; exactly one overload.
* `EXECUTE` revoked from `public` and granted to `anon` and `authenticated`,
  as for the other Discovery reads.
* The published-state predicate is fixed inside the read; no caller input
  can relax it.
* No direct client privilege is added on `clinics`, `clinic_locations`,
  `clinic_public_profiles`, or any other table or view.
* The BR-5 normalization is its own internal helper,
  `clinic_display_name_search_key(text)`, executable by no client role
  (`anon`, `authenticated`, `service_role`). It is independent of
  `professional_clinic_search_key`, which stays unchanged, and the read
  shares no authorization helper with professional reads.

---

## 5. Mobile Presentation

The Clinic list (`/clinics`) — the same screen for Anonymous Visitors and
Guardians:

* Heading and support text, a compact one-line search field, and the existing
  **Cerca de mí / Nearby** and **Mapa / Map** shortcuts. The shortcuts remain
  available in every state of the list, including errors; their routes are
  unchanged.
* Rows are compact, whole-row pressable cards opening `/clinics/[id]` by
  `clinic_id`: a generic Clinic icon, the display name (or the localized
  unnamed-Clinic label), and one supporting line — the address with a
  location pin when present, otherwise the description, otherwise nothing.
  No images, services, ratings, availability, distance, or filters.
* Every row comes from the page itself. No row triggers a further read.
* Pages of 20 with **Cargar más / Load more** while `has_more`. The list never
  downloads every Clinic to search or paginate on the device, and never shows
  a Clinic twice (deduplicated by `clinic_id`).
* At most one page read is in flight; an answer to an earlier search, or to a
  screen no longer shown, is ignored.
* The search is sent after a 300 ms pause, at once when submitted or cleared,
  and is limited to 100 characters. A new search withdraws the previous rows
  and cursor at once and shows the loading state.
* Empty states are distinct: no published Clinic at all, and "no Clinic
  matches" — shown only once the new search's first page arrived empty.
* A failed first page shows a calm error with **Reintentar / Retry**, keeping
  the search field and shortcuts. A failed **Load more** keeps the rows shown
  and offers a retry of the same cursor. Raw backend text is never shown.
* Returning from a Clinic's public profile keeps the search, every loaded page,
  and the position. The list is not re-read on focus. Loaded pages are
  discarded only by a new search, a retry of the first page, or a new visit to
  the screen. Rows already shown may be stale (`SPEC-DIS-001` §6); the
  Clinic's public profile re-reads and shows its own unavailable state.

---

## 6. Scenarios

### Scenario: Anonymous Visitor searches without accents

Given "Clínica Centro" and "Hospital Norte" are published

When an Anonymous Visitor searches "clinica"

Then "Clínica Centro" is returned
And "Hospital Norte" is not returned
And authentication is not required

---

### Scenario: Guardian sees the same results

Given the same published Clinics
And Maria is an authenticated Guardian

When Maria searches "clinica"

Then she receives exactly the rows an Anonymous Visitor receives

---

### Scenario: Unpublished Clinic is never found

Given "Clínica Sur" exists and is not published

When any caller searches "sur"

Then "Clínica Sur" is not returned
And the result is the same as if "Clínica Sur" did not exist

---

### Scenario: Clinic without a Location is listed

Given "Clínica Oeste" is published and has no Location

When the Clinic list is read

Then "Clínica Oeste" is returned with no address

---

### Scenario: Alphabetical keyset pages

Given 45 published Clinics

When the first page is read, then the next two with the returned cursors

Then the pages hold 20, 20 and 5 Clinics in alphabetical order
And no Clinic is repeated or skipped
And the last page has `has_more = false`

---

### Scenario: Duplicate display names stay distinct

Given two published Clinics named "Animalia"

When the Clinic list is read

Then both are returned, ordered by `clinic_id`, each opening its own profile

---

### Scenario: Back from a Clinic keeps the list

Given a Guardian loaded three pages for the search "vet"
And opened a Clinic's public profile

When the Guardian returns to the list

Then the search, the three pages, and the position are kept
And no read is made

---

## 7. Relevant Invariants

* **INV-005 — Organization and Clinic are different concepts.**
* **INV-014 — Anonymous public discovery is allowed.**

---

## 8. Dependencies

* SPEC-DIS-001 — Discover Published Clinics
* SPEC-CLI-002 — Set Clinic Location
* SPEC-CLI-003 — Publish Clinic
* SPEC-CLI-004 — Manage Clinic Public Profile

---

## 9. Out of Scope

* searching by address, area, service, specialty, or Organization;
* filters (`REQ-DIS-005`, Later);
* ranking, relevance, or personalization;
* public imagery or branding (`SPEC-CLI-004` BR-21);
* Appointment availability;
* changes to Nearby (`SPEC-DIS-002`) or Map (`SPEC-DIS-003`) Discovery;
* total counts;
* any persisted search index or database extension.

---

## 10. Verification Notes

Verification must demonstrate that:

1. the read is callable by `anon` and `authenticated`, with identical results;
2. only Clinics eligible under `SPEC-DIS-001` are returned; unpublished and
   nonexistent Clinics never are, and cannot be distinguished;
3. a published Clinic without a Location is returned with `address_text`
   `null`, and one with a Location carries exactly its public address;
4. each Clinic appears at most once per page;
5. the search is accent-, case-, and whitespace-insensitive per BR-5, literal
   for `%`, `_` and `\`, and matches only the display name;
6. order is display name then `clinic_id`, including duplicate names;
7. keyset round-trips taken from real responses neither repeat nor skip, and
   `has_more` and the next cursor reflect the last returned row;
8. a cursor naming an unknown or unpublished Clinic reveals nothing;
9. invalid limit, half cursor, and an over-long search fail with `22023`;
10. no table or view privilege is added, the internal normalization helper is
    executable by no client role, and `professional_clinic_search_key` and the
    existing Discovery reads are unchanged;
11. the read writes nothing;
12. the mobile list reads pages of 20, never re-reads on focus, keeps loaded
    pages when returning from a Clinic, discards them on a new search,
    ignores late answers, never shows a Clinic twice, and offers retries for
    first-page and load-more failures;
13. the Nearby and Map shortcuts remain available.

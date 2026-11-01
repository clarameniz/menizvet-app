# SPEC-CLI-007 — View Managed Clinic Configuration

**Status:** APPROVED
**Requirements:** REQ-CLI-002, REQ-CLI-003, REQ-CLI-005, REQ-ORG-005, REQ-ORG-008
**Domain:** Clinics
**Priority:** P1

## 1. Intent

Allow an authorized professional to inspect the current configuration of a
Clinic they manage, including a Clinic that is not published, so that the
Clinic can be configured, published, and unpublished without SQL or developer
intervention.

This Specification also defines the derived self-service concepts that explain
whether a Clinic can be published, whether it is publicly discoverable, and
whether its known online-Appointment configuration is complete, and the
professional settings overview that presents them.

It is the read side of Clinic self-service Phase 1. The writes it supports are
governed by:

- `SPEC-CLI-004` — Manage Clinic Public Profile;
- `SPEC-CLI-002` — Set Clinic Location;
- `SPEC-CLI-003` — Publish Clinic (publication and unpublication);
- `SPEC-APT-013` — Manage Appointment Availability (scheduling timezone,
  BR-43–BR-56 and BR-76).

---

## 2. Clinic self-service Phase 1 scope

Clinic self-service Phase 1 applies to a pre-existing Clinic, established
through trusted provisioning or `SPEC-CLI-001`. It covers:

- this managed Clinic configuration read;
- public profile and contact editing (`SPEC-CLI-004`);
- location editing (`SPEC-CLI-002`);
- scheduling timezone editing (`SPEC-APT-013` BR-76);
- publication status, Publish, and Unpublish (`SPEC-CLI-003`);
- the professional settings overview (§7).

It deliberately excludes (§10):

- Clinic creation;
- Opening Hours editing;
- Service Offerings editing;
- staff management (Invitations, acceptance, Membership ending,
  responsibilities);
- Veterinarian Clinic Assignment and Veterinarian Availability;
- clinical tooling.

---

## 3. Preconditions

- The acting User exists and is authenticated.
- The acting User has a current Organization Membership in the Organization
  that operates the target Clinic.
- The acting User currently holds at least one of the Clinic capabilities
  listed in BR-2 for the target Clinic.

---

## 4. Business Rules

### BR-1 — The read returns the Clinic's current self-service configuration

The professional management read

    get_managed_clinic_profile(p_clinic_id uuid) returns jsonb

returns exactly one JSON object with this canonical shape:

```text
{
  "clinic_id": uuid,
  "is_published": boolean,
  "scheduling_timezone_name": text | null,
  "public_profile": null | {
    "display_name": text | null,
    "description": text | null,
    "public_phone": text | null,
    "public_email": text | null,
    "website": text | null
  },
  "location": null | {
    "address_text": text,
    "latitude": float8,
    "longitude": float8
  }
}
```

- `is_published` is the Clinic's persisted publication state (`SPEC-CLI-003`).
- `scheduling_timezone_name` is the Clinic's current scheduling timezone
  (`SPEC-APT-013` BR-43), or `null` when none has been configured.
- `public_profile` is `null` when the Clinic has no stored public profile;
  otherwise it carries the five stored values, each `null` when absent
  (`SPEC-CLI-004`).
- `location` is `null` when the Clinic has no stored location; otherwise it
  carries the stored address text and coordinates (`SPEC-CLI-002`).

Values are returned exactly as stored. The read does not normalize, derive,
or default any value, and it does not invent placeholder data for missing
configuration.

All members are always present; absence is represented by `null`, never by an
omitted member.

---

### BR-2 — Authorization requires a Clinic self-service capability

The read is allowed when the acting User currently holds, for the target
Clinic, at least one of:

- `CLINIC_MANAGE_PUBLIC_PROFILE`;
- `CLINIC_MANAGE_LOCATION`;
- `CLINIC_MANAGE_PUBLICATION`;
- `CLINIC_MANAGE_OPENING_HOURS`,

evaluated by the same authoritative Clinic-capability evaluation used by every
protected Clinic operation (`SPEC-ORG-005`).

Under the Phase 1 responsibility mapping these are held by an
Organization-scoped `OWNER` or `ADMINISTRATOR` and by a Clinic-scoped
`ADMINISTRATOR` for their own Clinic. `RECEPTIONIST`, `VETERINARIAN`, a
Veterinarian Clinic Assignment, bare Organization Membership, and any
responsibility in another Organization do not grant the read.

Holding any one listed capability returns the full payload. Every field in it
is either public information when published or Clinic scheduling
configuration that every listed capability holder already manages; no field is
private Organization, User, Pet, Appointment, commercial, or medical
information.

The read does not authorize any change. Every write re-authorizes itself with
its own capability.

---

### BR-3 — The read does not depend on publication or Entitlement

The read works for published and unpublished Clinics alike.

It does not require any professional Entitlement or Subscription state
(`SPEC-SUB-003`). Understanding existing configuration is not paid
professional activity, and the read remains available after Entitlement loss.

---

### BR-4 — Nonexistent and inaccessible Clinics are indistinguishable

A nonexistent Clinic and a Clinic the acting User may not manage produce the
same failure: SQLSTATE `42501` with the same message as any other
inaccessible management read.

The outcome must not reveal whether the Clinic exists, whether it is
published, or which capability is missing.

An unauthenticated caller is rejected as unauthenticated (`28000`) before any
Clinic is considered.

---

### BR-5 — The read is side-effect free and non-locking

The read:

- modifies no domain state;
- takes no row lock and does not wait for, or block, configuration writes;
- observes one consistent snapshot, so `is_published`, the profile, the
  location, and the timezone it returns were current together;
- is a `STABLE` read operation.

No direct table access is granted to clients. The Clinic tables remain
accessible only through approved trusted operations.

---

### BR-6 — The read excludes configuration owned by other reads

The read does not return:

- the standard Appointment duration;
- Appointment Availability (recurring periods, exceptions, or revision);
- Opening Hours;
- Service Offerings;
- Subscription or Entitlement information;
- Organization Members, responsibilities, or Clinic Assignments.

These are available through their own approved reads and context:

- `SPEC-APT-013` BR-74 for the standard duration and Appointment
  Availability;
- `SPEC-CLI-006` and `SPEC-CLI-005` management reads for Opening Hours and
  Service Offerings;
- `SPEC-ORG-007` for Organization Entitlement flags and capabilities;
- `SPEC-ORG-008` for the Clinic's capabilities for the acting User.

The scheduling timezone appears in this read as well as in the Appointment
Availability and Opening Hours reads because Clinic self-service edits it
(`SPEC-APT-013` BR-76). All of them return the same stored value.

---

### BR-7 — Ready to publish

A Clinic is **ready to publish** exactly when the backend publication
prerequisites of `SPEC-CLI-003` are satisfied:

- the Clinic has a valid, non-empty public display name; and
- the Clinic has a stored location.

Derived from the read:

    ready_to_publish =
        public_profile is not null
        and public_profile.display_name is not null
        and location is not null

No other configuration — scheduling timezone, standard duration, Appointment
Availability, Opening Hours, Service Offerings, or Subscription — affects
readiness to publish.

---

### BR-8 — Published (discoverable)

A Clinic is **published** exactly when its persisted publication state is
published (`is_published = true`).

While a Clinic is published, existing integrity rules keep its required
display name and location present (`SPEC-CLI-003` BR-14). A published Clinic
is eligible for public Discovery (`SPEC-CLI-003` BR-5); individual Discovery
queries may still exclude it through their own filters, such as a radius or
viewport.

---

### BR-9 — Online Appointment setup complete

**Online Appointment setup complete** is an advisory derived configuration
status. It holds when all of the following hold:

1. the Clinic is published (BR-8);
2. the Clinic has a valid scheduling timezone (`SPEC-APT-013` BR-43);
3. the Clinic has a configured standard Appointment duration
   (`SPEC-APT-013` BR-57, BR-62);
4. the Clinic's Appointment Availability has current or future scheduling
   configuration: at least one recurring Clinic Appointment Availability
   period, or at least one `OPEN` Clinic Appointment Availability exception
   whose local date is not before the Clinic-local current date in the
   Clinic's scheduling timezone;
5. the Clinic's Veterinary Organization currently holds the
   `APPOINTMENT_MANAGEMENT` professional Entitlement (`SPEC-APT-014` BR-4).

This derived status means the known configuration prerequisites for online
Appointment requests are present. It does not guarantee that any specific
candidate time exists.

Configuration that satisfies this status may still yield zero candidate times,
for example when:

- every Availability period is shorter than the standard duration;
- every remaining Availability falls on dates closed by exceptions, or in the
  past, within the requested horizon;
- daylight-saving transitions make the candidate positions nonexistent or
  ambiguous;
- the configuration changes between the overview read and a Guardian read.

Only the Guardian candidate read (`SPEC-APT-014`) and `request_appointment`
(`SPEC-APT-001`) determine actual candidates and requests. This status must not
be named or presented as "bookable" and must not be used to accept, reject, or
filter any operation.

Veterinarian Availability, Opening Hours, and Service Offerings are not part of
this status: none of them is required by Guardian candidate generation or
Appointment requests.

---

### BR-10 — Derived statuses are not persisted

Ready to publish, published, and online Appointment setup complete are
computed from current authoritative state each time they are presented.

No readiness, completeness, or setup state is persisted, cached as
authoritative, or maintained by triggers. No rules engine is introduced: each
status is the conjunction of the conditions listed above.

A client may compute these statuses from:

- this read;
- the Appointment Availability management read (`SPEC-APT-013` BR-74);
- the professional context Entitlement flags (`SPEC-ORG-007`).

Such client computation is advisory. Every write and every Guardian-facing
read re-evaluates its own authoritative rules.

---

### BR-11 — Professional settings overview explains what is missing

The professional Clinic settings overview presents the configuration needed
for a Clinic to be found and to receive online Appointment requests, using
plain product language. Conceptually it shows:

| Item | Shown as complete when | Fixed in |
| --- | --- | --- |
| Clinic profile / name | the display name is present | Profile editor (`SPEC-CLI-004`) |
| Location / map position | a location is stored | Location editor (`SPEC-CLI-002`) |
| Scheduling timezone | a timezone is configured | Timezone editor (`SPEC-APT-013` BR-76) |
| Appointment duration | a standard duration is configured | Appointment hours (`SPEC-APT-013`) |
| Appointment hours | BR-9 condition 4 holds | Appointment hours (`SPEC-APT-013`) |
| Publication | published / not published | Publish or Unpublish on the overview (`SPEC-CLI-003`) |

It also presents, as separate answers:

- whether the Clinic can currently be found by the public (BR-8);
- whether the known setup for online Appointment requests is complete (BR-9),
  worded so that it does not promise available times.

Publication and online Appointment setup are presented as distinct concepts:
a Clinic may be published without accepting online requests, and Publish does
not require scheduling configuration.

Where the Organization lacks `APPOINTMENT_MANAGEMENT`, the overview may show a
calm plan notice explaining that online Appointment requests are not available
under the Organization's current plan. It must not expose Subscription
states, provider data, commercial dates, Entitlement identifiers, SQL
terminology, or SQLSTATEs. This uses only information already exposed to the
acting User by `SPEC-ORG-007`.

Every item the acting User can fix navigates to the editor that fixes it. An
item the acting User cannot fix (because they lack the editor's capability) is
shown without an edit action and, where helpful, with guidance to ask a Clinic
administrator. A missing requirement must never leave the professional without
an explanation of why the Clinic is not discoverable or cannot receive online
requests.

When the Appointment Availability read is unavailable to the acting User or
fails, the overview shows the scheduling items as unknown rather than as
complete or missing, and still shows the items derived from this read.

---

### BR-12 — Clinic settings information architecture

The professional Clinic surface is organized as:

```text
Clinic
  Schedule
  Appointment hours
  Clinic settings
      Overview / readiness   (includes Publication: Publish / Unpublish)
      Profile
      Location
      Timezone
```

- The Clinic settings entry is shown only to a professional whose advisory
  Clinic capabilities (`SPEC-ORG-008`) include at least one capability listed
  in BR-2.
- Each editor and action inside Clinic settings is individually gated by its
  own capability: Profile by `CLINIC_MANAGE_PUBLIC_PROFILE`, Location by
  `CLINIC_MANAGE_LOCATION`, Timezone by `CLINIC_MANAGE_OPENING_HOURS`, Publish
  and Unpublish by `CLINIC_MANAGE_PUBLICATION`.
- Configuration editors are not exposed as separate top-level Clinic actions.
- Client gating is advisory. Every read and write re-authorizes server-side,
  and an authorization failure is shown as calm access-lost guidance.

Opening Hours and Service Offerings editors are not part of Phase 1 Clinic
settings (§10).

---

### BR-13 — Editors re-read authoritative state

Every Clinic settings editor:

1. initializes its local draft from a fresh management read;
2. keeps Save disabled while the draft is unchanged, invalid, or a save is in
   flight;
3. after a successful save, re-reads and presents the authoritative state;
4. after a failed or lost save, re-reads; if the authoritative state equals
   the submitted values (after the backend's own normalization), the save is
   treated as successful; otherwise calm mapped copy is shown;
5. never shows raw backend text.

Concurrency is last-write-wins for the profile, the location, and the
timezone, and idempotent for Publish and Unpublish (§9).

---

## 5. Scenarios

### Scenario: Administrator reads an unpublished, unconfigured Clinic

Given Animalia Getafe exists and is not published
And it has no public profile, no location, and no scheduling timezone
And Maria is an Organization Administrator of Animalia Veterinary Group

When Maria reads the managed configuration of Animalia Getafe

Then the result has `is_published` false
And `scheduling_timezone_name`, `public_profile`, and `location` are `null`
And the settings overview shows the profile name, location, and timezone as
missing and the Clinic as not ready to publish

---

### Scenario: Partial profile is returned as stored

Given Animalia Getafe has a public profile with a description and phone but no
display name

When an authorized administrator reads its managed configuration

Then `public_profile.display_name` is `null`
And the description and phone are returned as stored
And the Clinic is not ready to publish

---

### Scenario: Published Clinic is returned with its configuration

Given Animalia Madrid Centro is published with a display name, location, and
scheduling timezone

When an authorized administrator reads its managed configuration

Then the result has `is_published` true and all stored values

---

### Scenario: Receptionist cannot read managed configuration

Given Carlos is a Receptionist at Animalia Madrid Centro

When Carlos reads the managed configuration of Animalia Madrid Centro

Then the read is denied with `42501`

---

### Scenario: Nonexistent and inaccessible Clinics are indistinguishable

Given Maria administers Animalia Veterinary Group only

When Maria reads the managed configuration of a VetCare Clinic
And Maria reads the managed configuration of a Clinic identifier that does not
exist

Then both reads fail with the same `42501` outcome

---

### Scenario: Read works without Entitlement

Given Animalia Veterinary Group's Subscription is `EXPIRED`

When an authorized administrator reads the managed configuration of Animalia
Madrid Centro

Then the configuration is returned

---

### Scenario: Online Appointment setup complete does not promise candidates

Given Animalia Madrid Centro is published, has `Europe/Madrid`, a 30-minute
standard duration, a recurring Monday period 09:00–09:20, and its Organization
holds `APPOINTMENT_MANAGEMENT`

When the settings overview is shown

Then online Appointment setup is presented as complete
And no wording claims that times are available
And the Guardian candidate read may still return no candidates, because the
period is shorter than the standard duration

---

### Scenario: Published Clinic without scheduling configuration

Given Animalia Getafe is published
And it has no standard Appointment duration

When the settings overview is shown

Then the Clinic is shown as publicly discoverable
And online Appointment setup is shown as incomplete, with Appointment duration
as the missing item linking to Appointment hours

---

### Scenario: Organization lacks APPOINTMENT_MANAGEMENT

Given Animalia Madrid Centro is otherwise fully configured and published
And Animalia Veterinary Group does not hold `APPOINTMENT_MANAGEMENT`

When the settings overview is shown

Then online Appointment setup is shown as incomplete
And a calm plan notice explains that online Appointment requests are not
available under the current plan
And no Subscription state, date, or Entitlement identifier is shown

---

## 6. Edge Cases

### Stored timezone no longer recognized

If a stored timezone stops being a valid named timezone (for example after a
timezone-database change), the read still returns the stored value exactly.
Online Appointment setup complete is then not satisfied, because condition 2
requires a valid timezone; the timezone item should be presented as needing
attention.

### Capabilities change while the overview is open

The overview's capability gating is advisory. A later read or write that is
denied shows calm access-lost guidance and does not reveal the reason.

### Clinic display name is absent in the Clinic list

The professional Clinic list may show a Clinic without a display name
(`SPEC-ORG-008` BR-9). Clinic settings remains reachable for it.

---

## 7. Existing Clinics and compatibility

- No backfill is required. Existing Clinics are read as they are stored;
  missing or partial configuration is presented as missing.
- Unpublished Clinics become manageable through this read and the Phase 1
  editors.
- Published Clinics keep their public behavior unchanged.
- No public Guardian or anonymous read changes in response to this
  Specification. Changes made through Clinic self-service are visible on
  subsequent live public reads according to the existing Discovery,
  publication, and candidate rules.

---

## 8. Relevant Invariants

- **INV-005 — Organization and Clinic are different concepts.**
- **INV-014 — Anonymous public discovery is allowed.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 9. Concurrency

Phase 1 Clinic self-service deliberately uses last-write-wins for the public
profile (`SPEC-CLI-004`), the location (`SPEC-CLI-002`), and the scheduling
timezone (`SPEC-APT-013` BR-75, BR-76). No revision token is introduced for
them. Publish and Unpublish are idempotent state operations
(`SPEC-CLI-003`).

These are deliberate decisions, not omissions: each is a low-frequency
operation, performed by few administrators, on values the actor sees in full
when editing. Clients must re-read after every save and reconcile lost
responses from authoritative state (BR-13).

---

## 10. Out of Scope

This Specification does not define:

- Clinic creation, which remains with trusted provisioning and
  `SPEC-CLI-001` and requires a separate decision before any self-service
  surface (`ADR-009` is unchanged);
- Opening Hours management (`SPEC-CLI-006`) and Service Offerings management
  (`SPEC-CLI-005`); they are informational, block neither publication nor
  Appointment coordination, and their existing management reads and writes
  remain available for later self-service slices;
- staff Invitation, acceptance, Membership ending, and responsibility changes,
  which remain separate and are the next major product area after Clinic
  self-service, subject to later prioritization;
- Veterinarian Clinic Assignment and Veterinarian Availability;
- clinical tooling;
- a persisted readiness state or rules engine;
- candidate-time previews;
- publication history or a publication timestamp.

---

## 11. Dependencies

- SPEC-CLI-001 — Create Clinic
- SPEC-CLI-002 — Set Clinic Location
- SPEC-CLI-003 — Publish Clinic
- SPEC-CLI-004 — Manage Clinic Public Profile
- SPEC-APT-013 — Manage Appointment Availability
- SPEC-APT-014 — View Guardian Requestable Appointment Times
- SPEC-ORG-005 — Evaluate Organization Responsibilities and Capabilities
- SPEC-ORG-007 — View My Professional Context
- SPEC-ORG-008 — View My Professional Clinics
- SPEC-SUB-003 — Evaluate Professional Entitlements
- SPEC-ID-003 — Authenticate User

---

## 12. Verification Notes

Verification must demonstrate that:

### Managed read

1. the read returns exactly the canonical shape of BR-1, with every member
   present and absent values as `null`;
2. an unpublished Clinic is returned with `is_published` false;
3. a published Clinic is returned with `is_published` true and its stored
   values;
4. a Clinic with no profile returns `public_profile` `null`; a partial profile
   returns its stored values with absent fields `null`;
5. a Clinic with no location returns `location` `null`;
6. a Clinic with no scheduling timezone returns `scheduling_timezone_name`
   `null`;
7. each of `CLINIC_MANAGE_PUBLIC_PROFILE`, `CLINIC_MANAGE_LOCATION`,
   `CLINIC_MANAGE_PUBLICATION`, and `CLINIC_MANAGE_OPENING_HOURS` alone is
   sufficient — exercised through Organization-scoped `OWNER` and
   `ADMINISTRATOR` and a Clinic-scoped `ADMINISTRATOR` for its own Clinic;
8. a Clinic-scoped `ADMINISTRATOR` of another Clinic, an Organization- or
   Clinic-scoped `RECEPTIONIST`, a `VETERINARIAN` with a current Clinic
   Assignment, a User with no Membership, an ended Membership or Grant, a
   member of another Organization, and an anonymous caller are denied;
9. a nonexistent Clinic and an inaccessible Clinic produce the same `42501`
   outcome;
10. the read succeeds without any professional Entitlement, including with a
    `PENDING` or `EXPIRED` Subscription;
11. the read takes no row lock on the Organization or Clinic and does not wait
    behind a concurrent configuration write;
12. the read is `STABLE` and changes no state;
13. the read returns no duration, Availability, Opening Hours, Service
    Offerings, Subscription, or Entitlement data, and no other Clinic's data;
14. no direct table privilege is granted to `anon` or `authenticated`;

### Readiness

15. ready to publish holds exactly when a non-empty display name and a
    location are stored, and is unaffected by timezone, duration,
    Availability, Opening Hours, Service Offerings, and Subscription;
16. published equals the persisted publication state;
17. online Appointment setup complete requires all five BR-9 conditions and
    fails when any one is absent;
18. an `OPEN` exception for a past Clinic-local date alone does not satisfy
    condition 4, while a recurring period or a current/future `OPEN`
    exception does;
19. the overview never presents online Appointment setup complete as a
    guarantee of available times, and a configuration with periods shorter
    than the standard duration is shown as complete while the Guardian
    candidate read returns no candidates;
20. no readiness state is persisted;
21. the overview shows every missing item with navigation to its editor when
    the acting User holds the editor's capability, and guidance otherwise;
22. the plan notice appears only when `APPOINTMENT_MANAGEMENT` is absent and
    exposes no Subscription or Entitlement internals;
23. the Clinic settings entry appears only with at least one BR-2 capability,
    and each editor and action is individually capability-gated.

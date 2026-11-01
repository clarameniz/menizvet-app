# SPEC-PET-005 — Update Pet Profile

**Status:** APPROVED  
**Requirements:** REQ-PET-005  
**Domain:** Pets and Guardianship  
**Priority:** P1

## 1. Intent

Allow an authorized current Guardian to maintain the non-clinical profile
information of a Pet.

Updating the Pet Profile must preserve the identity of the Pet.

Profile changes must not:

- create a new Pet;
- replace the Pet domain identity;
- alter Guardianship relationships;
- rewrite Appointment history;
- rewrite medical history;
- alter historical clinical provenance.

The Pet Profile represents current non-clinical information about the Pet.

---

## 2. Preconditions

- The Pet exists.
- The acting User exists.
- The acting User is authenticated.
- The acting User has a current active Guardianship relationship with the Pet.
- The requested changes concern supported non-clinical Pet Profile
  information.
- After the update, all profile information required by `SPEC-PET-001` remains
  valid and present.

---

## 3. Business Rules

### BR-1 — Current Guardian may update Pet Profile

A User with a current active Guardianship relationship with the Pet may update
the Pet's supported non-clinical profile information.

Phase 1 does not define differentiated Guardian permission levels.

Therefore, every current active Guardian may maintain the Pet Profile.

---

### BR-2 — Pet Profile is shared between Guardians

A Pet has one current Pet Profile.

Several Guardians of the same Pet must not receive separate copies of that
profile.

Conceptually:

    Maria ───┐
             │
             ▼
            Luna
             ▲
             │
    Carlos ──┘

If Maria validly updates Luna's profile, Carlos subsequently sees the same
updated Pet Profile.

---

### BR-3 — Original Pet registrar has no permanent special editing authority

The User who originally registered the Pet does not retain special permanent
control over the Pet Profile merely because they created the Pet record.

Current Guardianship determines Phase 1 profile-maintenance authority.

---

### BR-4 — Former Guardian cannot update Pet Profile

A User whose Guardianship relationship has ended must not continue updating the
Pet Profile solely because they:

- registered the Pet;
- previously maintained the profile;
- previously were a Guardian.

Historical Guardianship is insufficient.

---

### BR-5 — Updating Pet Profile preserves Pet identity

Changing Pet Profile information must modify the existing Pet.

It must not create another Pet solely because mutable profile information has
changed.

For example:

    Luna
    name corrected

remains the same Pet domain entity.

---

### BR-6 — Required Pet information cannot be removed

Information required for a valid Pet under `SPEC-PET-001` must remain present
after an update.

An authorized Guardian may correct or replace a required value where allowed.

They must not leave the Pet in a state where required profile information is
missing or invalid.

---

### BR-7 — Optional Pet information may be added, changed, or removed

Supported optional Pet Profile information may be:

- added;
- corrected;
- changed;
- removed.

The absence of optional information must not make an otherwise valid Pet
invalid.

---

### BR-8 — Profile update is non-clinical

The Pet Profile workflow is intended for non-clinical Pet information.

It must not be used as an alternative mechanism for creating or modifying:

- diagnoses;
- Treatments;
- Vaccinations;
- Prescriptions;
- Laboratory Results;
- Imaging Results;
- Clinical Record Entries;
- Clinical Amendments.

Medical information follows the Medical Records domain.

---

### BR-9 — Current profile changes do not rewrite medical history

Changing current Pet Profile information must not alter historical:

- Clinical Encounters;
- Clinical Record Entries;
- Clinical Amendments;
- Clinical Attachments;
- clinical provenance.

The medical history remains associated with the same Pet identity.

---

### BR-10 — Pet name may change without creating new history

A Pet's current name may be corrected or changed where supported.

Changing the name must not:

- create another Pet;
- create another medical history;
- detach previous Appointments;
- detach previous Clinical Encounters.

Historical information remains associated with the same Pet identity.

---

### BR-11 — Profile corrections do not rewrite provider provenance

Changing Pet Profile information must not change which:

- Clinic;
- Veterinary Organization;
- Veterinarian;

historically provided care to the Pet.

---

### BR-12 — Profile updates do not change Guardianship

Updating Pet Profile information must not:

- add a Guardian;
- remove a Guardian;
- invite a Guardian;
- accept a Guardianship Invitation;
- end Guardianship.

Pet Profile and Guardianship lifecycle are separate concerns.

---

### BR-13 — Profile updates do not change Appointment lifecycle

Updating the Pet Profile must not:

- create an Appointment;
- cancel an Appointment;
- reschedule an Appointment;
- complete an Appointment;
- mark an Appointment `NO_SHOW`.

Existing Appointments remain associated with the same Pet.

---

### BR-14 — Profile updates do not alter Care Authorization

Updating Pet Profile information must not:

- grant Care Authorization;
- revoke Care Authorization;
- extend Care Authorization;
- change its care context.

Medical Access Control remains separate.

---

### BR-15 — Behavioral safety information remains optional

Behavioral or handling information relevant to the safety of:

- the Pet;
- veterinary professionals;
- other people;

may be maintained as optional Pet Profile information.

The absence of such information must not make the Pet Profile invalid.

---

### BR-16 — Behavioral safety information may be updated

An authorized Guardian may change behavioral safety information when their
understanding of the Pet changes.

For example, information concerning whether the Pet may behave aggressively in
certain situations may be updated over time.

The current Profile must not require an outdated behavioral statement to remain
unchanged forever.

---

### BR-17 — Behavioral information is contextual rather than permanent truth

Behavioral safety information must not be represented as a permanent universal
assumption about the Pet.

For example:

    "May become aggressive when handled while frightened"

must not become equivalent to:

    "This Pet is always aggressive."

The model must allow clinically and operationally useful caution without
stereotyping the Pet's behavior across every context.

---

### BR-18 — Optional behavioral information may be removed

Because behavioral safety information is optional, an authorized current
Guardian may remove it when it is no longer considered applicable.

Removing optional behavioral information must not invalidate the Pet Profile.

Historical clinical information that independently documented behavior must not
be deleted or rewritten as a consequence.

---

### BR-19 — Pet Profile must not overwrite clinical behavioral observations

A Guardian changing or removing current Pet Profile behavioral information must
not modify behavioral observations previously recorded as finalized clinical
information.

For example:

    Pet Profile:
    current handling note removed

does not mean:

    previous veterinary clinical observation is deleted

The two sources have different provenance and meaning.

---

### BR-20 — Current Pet Profile reflects current known non-clinical information

The Pet Profile represents the current maintained view of supported
non-clinical information.

Ordinary profile maintenance does not require preserving every historical value
of every mutable field unless another requirement explicitly requires such
history.

---

### BR-21 — Clinically significant history must not be hidden in Pet Profile

The system must not rely on mutable Pet Profile fields as the sole persistence
location for information that belongs in longitudinal medical history.

Clinically significant events or observations must follow the Medical Records
workflow where applicable.

---

### BR-22 — Unsupported fields cannot be introduced arbitrarily

The update workflow must accept only supported Pet Profile information.

A client must not be able to persist arbitrary domain fields merely by sending
additional properties.

The supported profile model is defined by the approved Pet Specifications.

---

### BR-23 — Profile validation applies on update

A changed value must satisfy the applicable validation rules before the update
is accepted.

An existing valid Pet must not be moved into an invalid profile state through
ordinary editing.

---

### BR-24 — Unchanged fields remain unchanged

Updating one part of the Pet Profile must not require overwriting unrelated
profile information.

For example:

    update profile image

must not silently clear:

    birth information
    species
    behavioral safety information

where those fields were not part of the intended change.

---

### BR-25 — Concurrent updates must not silently erase unrelated valid changes

Where several Guardians update the same Pet Profile concurrently, the final
state must not silently lose unrelated valid changes merely because both Users
started from older copies of the Profile.

The exact concurrency-control mechanism is architectural.

---

### BR-26 — Current Guardians may see updates made by another Guardian

A valid Pet Profile update is a change to the shared Pet Profile.

Another current Guardian must not continue to receive a private stale version
as though their Guardian relationship owned a separate profile.

Client synchronization is architectural.

---

### BR-27 — Profile update preserves modification context where required

The system should be capable of identifying:

- the Pet;
- the acting User;
- when the Profile was modified;

where operational or security traceability requires it.

This does not mean that every Pet Profile field requires immutable historical
versioning in Phase 1.

---

### BR-28 — Pet Profile update is not a Clinical Amendment

Correcting mutable non-clinical Pet Profile information does not require the
Clinical Amendment workflow.

Clinical Amendments apply to finalized clinical information.

---

### BR-29 — Updating current profile does not rewrite Appointment snapshots or history

Where historical Appointment information preserves Pet context, changing the
current Pet Profile must not create a new Appointment or alter its original
lifecycle history.

The Appointment remains associated with the same Pet identity.

---

### BR-30 — Profile changes survive provider changes

The Pet Profile belongs to the Pet rather than a Clinic or Veterinary
Organization.

Changing veterinary provider must not create a provider-specific Pet Profile.

---

### BR-31 — Clinic cannot edit Pet Profile solely through medical access

A Clinic or Veterinarian must not gain Guardian-style Pet Profile editing
authority merely because they:

- have Care Authorization;
- are treating the Pet;
- can access relevant medical history.

Professional medical access and Guardian Pet Profile maintenance are separate
capabilities.

---

### BR-32 — Veterinarian status alone cannot update Pet Profile

A User with a Veterinarian Professional Profile but no active Guardianship for
the Pet must not modify the Pet's Guardian-maintained Profile through this
workflow.

---

### BR-33 — Updating Pet Profile requires authenticated identity

Anonymous Visitors must not update Pet Profile information.

The operation requires an authenticated User with current Guardianship.

---

### BR-34 — Profile update is atomic

A successful Pet Profile update must leave the Pet in one coherent valid
Profile state.

The system must not expose a partially applied update that leaves required
information invalid or internally inconsistent.

---

### BR-35 — Failed update preserves previous valid Profile

If a requested update fails validation or cannot be committed successfully,
the previous valid Pet Profile must remain unchanged.

---

## 4. Pet Profile Information

The exact supported fields originate from `SPEC-PET-001`.

The update workflow must distinguish between:

### Required information

Information required for the Pet to remain valid under the Pet registration
rules.

Required information:

- may be corrected where permitted;
- may be replaced with another valid value;
- must not be removed without a valid replacement.

### Optional information

Supported optional Pet Profile information may be:

- added;
- changed;
- removed.

This includes optional behavioral or handling safety information.

Clinical information must not be maintained through ordinary Pet Profile
editing.

---

## 5. Scenarios

### Scenario: Guardian updates Pet name

Given Maria has an active Guardianship relationship with Luna

When Maria validly changes Luna's current profile name

Then the existing Pet Profile is updated
And Luna remains the same Pet domain entity
And Luna's Appointments remain associated with the same Pet
And Luna's medical history remains associated with the same Pet

---

### Scenario: Second Guardian sees shared Profile update

Given Maria and Carlos are both active Guardians of Luna
And Maria validly updates Luna's Pet Profile

When Carlos later views Luna

Then Carlos sees the updated shared Pet Profile
And a separate Carlos-specific copy of Luna is not created

---

### Scenario: Guardian who did not register Pet may update Profile

Given Maria originally registered Luna
And Carlos later became an active Guardian of Luna

When Carlos validly updates a supported Pet Profile field

Then the update may succeed
And original registration by Maria does not give Maria exclusive editing
authority

---

### Scenario: Former Guardian cannot update Profile

Given Carlos previously had an active Guardianship relationship with Luna
And that Guardianship has ended

When Carlos attempts to update Luna's Pet Profile

Then the operation is denied
And historical Guardianship alone is insufficient

---

### Scenario: Required information cannot be cleared

Given Luna has all Pet information required by `SPEC-PET-001`

When Maria attempts to remove a required field without providing a valid
replacement

Then the update is rejected
And Luna's previous valid Profile remains unchanged

---

### Scenario: Required information may be corrected

Given Luna has a required Profile value that Maria discovers is incorrect
And the replacement value satisfies the applicable validation rules

When Maria submits the correction

Then Luna's existing Pet Profile is updated
And a new Pet is not created

---

### Scenario: Optional information may be removed

Given Luna has optional Pet Profile information
And Maria is an active Guardian

When Maria removes that optional information

Then the update may succeed
And Luna's Profile remains valid

---

### Scenario: Guardian adds behavioral safety information

Given Maria is an active Guardian of Luna
And Luna currently has no behavioral safety information

When Maria adds information indicating that Luna may react aggressively when
handled while frightened

Then the information may be stored as optional Pet Profile information
And Luna's registration remains the same Pet identity

---

### Scenario: Behavioral information may later change

Given Luna's Pet Profile contains behavioral safety information
And Maria determines that the current Profile should be updated

When Maria changes the behavioral information

Then the current Pet Profile may reflect the new information
And the previous statement is not treated as a permanent universal truth about
Luna

---

### Scenario: Behavioral information may be removed

Given Luna has optional behavioral safety information
And Maria is an active Guardian

When Maria removes that information

Then the Pet Profile remains valid
And finalized clinical observations concerning Luna are not deleted or changed

---

### Scenario: Pet Profile update does not alter clinical record

Given Luna has finalized medical history from Animalia Madrid Centro
And Maria changes Luna's non-clinical Pet Profile

When Luna's medical history is subsequently viewed

Then the historical Clinical Record Entries remain intact
And their clinical provenance remains unchanged

---

### Scenario: Clinic professional cannot edit Guardian-maintained Pet Profile

Given Dr. Garcia has a valid Care Authorization context for Luna
And Dr. Garcia has no active Guardianship relationship with Luna

When Dr. Garcia attempts to update Luna's Pet Profile through the Guardian
maintenance workflow

Then the operation is denied
And medical-access authority does not imply Guardian Profile-editing authority

---

### Scenario: Updating one field does not clear another field

Given Luna has valid profile information including optional behavioral
information

When Maria updates only Luna's profile image

Then the requested image change may be applied
And unrelated existing profile information remains unchanged

---

### Scenario: Profile update does not affect Guardianship

Given Maria and Carlos are both active Guardians of Luna

When Maria updates Luna's Profile

Then Maria remains a Guardian
And Carlos remains a Guardian
And no Guardianship relationship is added or removed

---

### Scenario: Profile update does not affect existing Appointment

Given Luna has a `CONFIRMED` Appointment at Animalia Madrid Centro

When Maria validly updates Luna's Pet Profile

Then the Appointment remains `CONFIRMED`
And it remains associated with the same Pet

---

### Scenario: Invalid update preserves previous Profile

Given Luna currently has a valid Pet Profile

When Maria submits an invalid Profile update

Then the update is rejected
And Luna's previous valid Profile remains unchanged

---

## 6. Shared Guardian Model

Pet Profile ownership follows the Pet, not the individual Guardian.

Conceptually:

    Pet
    Luna
      │
      ├── Guardian: Maria
      └── Guardian: Carlos

      ↓

    One shared Pet Profile

Phase 1 gives current Guardians equivalent profile-maintenance capability.

Future differentiated Guardian permissions may refine this behavior if
required.

---

## 7. Pet Profile vs Medical History

Pet Profile answers questions such as:

    What is the Pet's current non-clinical information?

Medical history answers:

    What veterinary care, observations, diagnoses, treatments, and other
    clinical events occurred?

These concepts must remain separate.

For example:

    Pet Profile
    "May react aggressively when frightened"

may be current Guardian-provided context.

Whereas:

    Clinical Record
    "Patient attempted to bite during wound examination on 2026-09-10"

is professional clinical history.

Changing the first must not rewrite the second.

---

## 8. Required vs Optional Information

Profile maintenance preserves the distinction established at registration.

Conceptually:

    required field
        ↓
    may change
    cannot become absent

while:

    optional field
        ↓
    may be added
    may change
    may be removed

This allows the Pet Profile to evolve without making previously valid Pets
structurally incomplete.

---

## 9. Edge Cases

### Two Guardians edit the Profile at the same time

The system must protect against silently losing unrelated valid changes.

The exact concurrency strategy may use optimistic concurrency, versioning, or
another architectural mechanism.

---

### Pet information was originally entered incorrectly

A current Guardian may correct supported mutable Pet Profile information.

The correction modifies the existing Pet rather than creating another Pet.

---

### Wrong Pet was registered entirely

If a User accidentally created a separate Pet domain entity when they intended
to refer to an existing Pet, ordinary Profile editing must not merge the two
Pet identities.

Pet merging or duplicate-Pet resolution requires separate controlled behavior.

---

### Behavioral information conflicts between Guardians

Phase 1 gives current Guardians equivalent Pet Profile maintenance capability.

The last valid committed Profile state becomes the current maintained
information.

The system does not attempt to adjudicate Guardian disagreement in Phase 1.

A future differentiated or dispute-resolution model may refine this behavior.

---

### Current Pet name differs from name used historically

Historical information remains associated with the same Pet identity.

Presentation may use current Profile information where appropriate without
rewriting historical clinical provenance.

---

### Profile information may become clinically relevant

If information becomes part of professional clinical assessment, that clinical
observation must be documented through the Medical Records workflow.

The mutable Guardian Profile must not become the sole record of clinically
meaningful professional information.

---

## 10. Relevant Invariants

- **INV-002 — Pet identity is provider-independent.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-010 — Medical history follows the Pet.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 11. Dependencies

- SPEC-PET-001 — Register Pet
- SPEC-PET-002 — Invite Guardian
- SPEC-PET-003 — Accept Guardianship Invitation
- SPEC-PET-004 — View My Pets
- SPEC-ID-003 — Authenticate User

Historical and clinical separation additionally relates to:

- SPEC-MED-005 — View Pet Medical History

---

## 12. Out of Scope

This Specification does not define:

- creation of another Pet;
- Pet merging;
- duplicate-Pet resolution;
- Pet deletion;
- differentiated Guardian permissions;
- Guardian disagreement resolution;
- Guardianship invitation or removal;
- clinical record editing;
- medical history correction;
- clinical behavioral observations;
- immutable version history for every Pet Profile field;
- Clinic-side Pet Profile editing;
- Pet ownership transfer;
- deceased-Pet lifecycle;
- archival behavior.

---

## 13. Verification Notes

Verification must demonstrate that:

1. a current active Guardian may update supported Pet Profile information;
2. several current Guardians maintain one shared Pet Profile;
3. original Pet registrar status does not provide exclusive editing authority;
4. former Guardians cannot update through historical Guardianship;
5. Profile updates preserve Pet domain identity;
6. required registration information cannot be removed without a valid
   replacement;
7. optional Profile information may be added, changed, or removed;
8. behavioral safety information remains optional and editable;
9. behavioral information is not modeled as permanent universal truth;
10. removing Profile behavioral information does not delete finalized clinical
    observations;
11. Pet Profile updates do not modify Guardianship;
12. Pet Profile updates do not alter Appointment lifecycle;
13. Pet Profile updates do not alter Care Authorization;
14. Pet Profile updates do not rewrite medical history or clinical provenance;
15. Clinic medical access does not grant Guardian Profile-editing authority;
16. updating one Profile field does not silently clear unrelated fields;
17. invalid updates preserve the previous valid Profile;
18. concurrent updates must not silently lose unrelated valid changes;
19. Profile maintenance remains distinct from Medical Records behavior;
20. successful Profile updates behave atomically.
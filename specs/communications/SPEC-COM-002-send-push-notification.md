# SPEC-COM-002 — Send Push Notification

**Status:** APPROVED  
**Requirements:** REQ-COM-002  
**Domain:** Communications  
**Priority:** P1

## 1. Intent

Allow the system to send transactional push notifications to a User through
zero, one, or multiple currently eligible device notification destinations.

Push notifications support timely awareness of product events.

They are a communication mechanism.

They must not become:

- the source of domain truth;
- proof that the User received or read information;
- a substitute for authentication;
- a substitute for authorization;
- a container for unnecessarily sensitive medical information.

A single User may use several devices simultaneously.

The communication model must therefore not assume one push token per User.

---

## 2. Preconditions

For a push delivery attempt:

- a supported notification-triggering event exists;
- the intended User is identifiable;
- the User is eligible to receive the applicable notification type;
- zero or more active Push Registrations may exist for that User;
- each attempted destination is associated with the intended User context;
- the push content satisfies applicable privacy and data-minimization rules;
- trusted infrastructure creates or validates the notification request.

Absence of an eligible Push Registration must not corrupt the originating
domain operation.

---

## 3. Push Registration Model

A User may have:

    zero Push Registrations

    one Push Registration

    multiple Push Registrations

Conceptually:

    Maria
    ├── iPhone
    │   └── Push Registration A
    │
    └── iPad
        └── Push Registration B

The Push Registration represents a technical notification destination.

It does not represent:

- another User;
- another session identity;
- another Guardian;
- another Organization Member.

---

## 4. Business Rules

### BR-1 — User may have multiple active Push Registrations

The communication model must support more than one active Push Registration for
the same User.

Registering another device must not require replacing an unrelated active
device registration.

---

### BR-2 — User may have no Push Registrations

A valid User account does not require push notification capability.

A User may have no active Push Registration because:

- no supported device has registered;
- operating-system permission is unavailable;
- the User signed out from previous devices;
- existing provider tokens became invalid.

The User remains a valid domain User.

---

### BR-3 — Push token must not be stored as a single User property

The domain must not assume a model equivalent to:

    User.push_token

where only one technical notification destination can exist.

Push destinations must remain independently manageable.

---

### BR-4 — Push Registration belongs to a User context

An active Push Registration used for private transactional communication must
be associated with the User for whom notifications are being delivered.

A destination previously associated with another User must not receive the
current User's private notifications.

---

### BR-5 — Push Registration is not User identity

A provider token, device token, or equivalent technical identifier must not
become the domain identity of the User.

Tokens may change while the User remains the same domain User.

---

### BR-6 — Push Registration is not authentication proof

Possession of a valid push token must not establish that:

- a User is authenticated;
- a User owns a domain account;
- a User has a particular capability.

Authentication remains governed by the Identity domain.

---

### BR-7 — Device notification permission and User preference are distinct

The system must distinguish conceptually between:

    User wants this notification type

and:

    this device currently permits push delivery

A User preference cannot force an operating system to deliver notifications.

Likewise, operating-system permission alone must not imply that every product
notification should be sent.

---

### BR-8 — Device permission is device-specific

One device may allow push notifications while another device associated with
the same User does not.

For example:

    Maria
    ├── iPhone → eligible
    └── iPad   → unavailable

The inability to notify the iPad must not prevent the iPhone from remaining an
eligible destination.

---

### BR-9 — Notification preference may be category-specific

Where the product supports communication preferences, a User may be able to
control categories of optional push communication.

The exact preference model and UI are outside this Specification.

Mandatory security behavior must not be assumed to be controlled by ordinary
marketing-style preferences.

---

### BR-10 — Push is caused by an approved product event

A transactional push notification must correspond to a supported domain,
Identity, or operational event.

The client must not independently fabricate authoritative notification events.

---

### BR-11 — Push notification is not the source of domain truth

For example:

    Appointment CONFIRMED
        ↓
    push notification

not:

    push notification sent
        ↓
    therefore Appointment is CONFIRMED

The Appointment domain remains authoritative.

---

### BR-12 — Push retry must not repeat originating domain operation

Retrying push delivery must not:

- confirm an Appointment again;
- cancel an Appointment again;
- create another Invitation;
- create another domain event;
- duplicate another originating operation.

Communication delivery and domain lifecycle are separate concerns.

---

### BR-13 — Delivery attempt does not imply delivery

Submitting a push message to a notification provider does not prove that the
notification reached the User's device.

---

### BR-14 — Provider acceptance does not imply User visibility

A provider reporting successful acceptance does not prove that:

- the device displayed the notification;
- the operating system permitted presentation;
- the User saw the notification;
- the User opened the notification.

---

### BR-15 — Push notification does not prove User acknowledgement

The system must not infer business acceptance or acknowledgement merely because
a push was sent or delivered.

For example:

    reschedule push delivered

does not mean:

    Guardian accepted reschedule

The applicable explicit domain workflow remains required.

---

### BR-16 — One logical User notification may target several destinations

Where the User has several eligible active Push Registrations, one logical
notification may result in several technical delivery attempts.

Conceptually:

    Appointment confirmed
            ↓
    notification for Maria
            ↓
    ├── iPhone
    └── iPad

This remains one User-facing communication event with multiple technical
destinations where the architecture chooses to represent it that way.

---

### BR-17 — Multiple device deliveries must not duplicate domain meaning

Delivering the same notification to two devices must not be interpreted as two
Appointment confirmations or two independent business events.

---

### BR-18 — Duplicate Push Registration must not create accidental duplicate delivery

The system should avoid retaining multiple equivalent current registrations
representing the same technical push destination for the same User.

The exact uniqueness and normalization mechanism is architectural.

---

### BR-19 — Push provider tokens may rotate

A push provider may replace or rotate a technical device token.

Token rotation must not:

- create another domain User;
- create another device owner;
- modify Guardianship;
- modify Organization Membership.

The Push Registration may be updated according to infrastructure requirements.

---

### BR-20 — Invalid provider destination must become ineligible

When trusted provider feedback establishes that a Push Registration is no
longer valid, that destination must not continue being treated as normally
deliverable.

The registration may be disabled or removed according to the architectural
lifecycle.

---

### BR-21 — Invalid destination does not affect other devices

If Maria's former iPhone token becomes invalid, Maria's valid iPad Push
Registration remains independently usable.

---

### BR-22 — Sign out makes the applicable device destination ineligible for private User notifications

When the User signs out from a device or client context, that context must no
longer receive private transactional push notifications intended for that
signed-out User.

For example:

    Maria signs out on iPhone
        ↓
    Maria's iPhone destination
    no longer receives Maria's private push

This must not necessarily disable Maria's separately authenticated iPad
destination.

---

### BR-23 — Sign out does not remove User notification preferences

Ending one authenticated session must not necessarily erase User-level
communication preferences.

Session state, device registration, and User preference are separate concepts.

---

### BR-24 — Another User signing into the same device must not inherit private notifications

A physical device may later be used by another User.

The system must not continue delivering Maria's private push notifications to a
destination now associated with Carlos.

The applicable Push Registration must be rebound, replaced, or otherwise made
safe before private notifications continue.

---

### BR-25 — Account recovery invalidation affects previous notification contexts

Where `SPEC-ID-005` invalidates previous authentication sessions after account
recovery, Push Registrations dependent on those obsolete authenticated contexts
must no longer provide private notification delivery until appropriately
re-established.

Account recovery must not leave a lost device receiving private notifications
through an obsolete session context.

---

### BR-26 — Push payload must minimize sensitive information

Push notifications may appear on:

- lock screens;
- notification centers;
- paired devices;
- operating-system previews.

Therefore, push payloads must contain only the minimum information required for
the notification purpose.

---

### BR-27 — Detailed medical information must not be placed in ordinary push payloads

Ordinary push notifications must not expose information such as:

- diagnoses;
- complete medical notes;
- laboratory-result details;
- Clinical Attachment contents;
- detailed protected medical history.

Where medical information is available inside the application, the push should
direct the User to authenticate and access it through the applicable
authorization workflow.

---

### BR-28 — Notification deep link does not grant authorization

A push notification may contain navigation context that allows the client to
open a relevant screen.

Possession of that navigation reference must not independently grant access to:

- Pet information;
- Appointments;
- Organization information;
- medical history;
- Clinical Attachments.

Current authentication and authorization must be evaluated when the protected
resource is accessed.

---

### BR-29 — Stale notification does not override current domain state

A User may open a notification after the underlying state has changed.

For example:

    Appointment CONFIRMED
        ↓
    push queued
        ↓
    Appointment CANCELLED
        ↓
    User later opens old push

The application must display the current authoritative Appointment state rather
than trusting the stale notification payload.

---

### BR-30 — Notification content may be localized

Push presentation may use the User's supported communication language where
available.

Localization must not change:

- originating domain event;
- recipient;
- authorization;
- Appointment state.

---

### BR-31 — Push provider is not domain authority

Provider callbacks may update technical delivery information.

They must not independently modify:

- Appointment lifecycle;
- Organization Membership;
- Guardianship;
- Subscription state;
- medical authorization.

---

### BR-32 — Duplicate provider callbacks must be idempotent

Repeated provider delivery events must not create:

- duplicate originating domain events;
- duplicate notification meaning;
- inconsistent current delivery state.

---

### BR-33 — Failed push must not rollback originating domain operation

For example:

    Appointment confirmed
        ↓
    push fails

must not ordinarily become:

    Appointment not confirmed

The domain operation remains authoritative.

---

### BR-34 — Push failure must not block another communication channel by assumption

A failed push attempt must not imply that:

- email cannot be sent;
- another device cannot be notified;
- another supported communication channel must fail.

Communication channels remain independently deliverable.

---

### BR-35 — Push notifications are not guaranteed communication

The product must not rely on successful push delivery as the only durable way
for a User to discover an important domain state.

Important information must remain available through the authoritative
application state.

Other transactional channels may additionally be used where required.

---

### BR-36 — Current application state remains authoritative after missed push

If Maria never receives an Appointment confirmation push, signing into the
application must still show the Appointment's actual current state.

---

### BR-37 — Communication dispatch occurs through trusted infrastructure

A manipulated client must not be able to send authoritative push notifications
pretending that a domain transition occurred when it did not.

---

### BR-38 — Push delivery may be operationally traceable

Where required, the system should be capable of determining:

- logical notification type;
- intended User;
- technical destination;
- delivery-attempt time;
- provider outcome.

This information must not require storing unnecessary sensitive payloads.

---

### BR-39 — Push registration data is sensitive infrastructure information

Provider tokens and equivalent destination identifiers must not be exposed as:

- public User Profile information;
- Organization-visible account data;
- analytics payloads without justification.

---

### BR-40 — Subscription termination does not erase required communication history

Commercial changes in a Veterinary Organization must not destructively erase
historical notification-delivery information where that information is retained
for security or operational purposes.

---

### BR-41 — Push Registration lifecycle does not change domain relationships

Creating, updating, disabling, or removing a Push Registration must not alter:

- User identity;
- Guardianship;
- Organization Membership;
- Veterinarian Professional Profile;
- Clinic Assignment;
- Appointment lifecycle.

---

### BR-42 — Failed registration update preserves safe notification behavior

If a Push Registration cannot be safely established or updated, the system must
not route private User notifications to an ambiguous or incorrectly associated
destination.

---

## 5. Push Registration Information

A Push Registration should support enough information to represent one
technical notification destination.

### Required where applicable

- Push Registration identity;
- associated User;
- provider destination token or reference;
- device/platform context;
- active or eligible state;
- creation or registration time.

### Useful technical context

- last successful update;
- provider;
- token invalidation state;
- notification permission or capability state where known.

The exact persistence representation is architectural.

The Push Registration must not become part of the User's public Profile.

---

## 6. Scenarios

### Scenario: User registers first device

Given Maria is authenticated on her iPhone
And the device has an eligible push destination

When the push destination is registered for Maria

Then Maria may have one active Push Registration
And Maria remains the same domain User
And no domain relationship is changed

---

### Scenario: User registers second device

Given Maria already has an active iPhone Push Registration
And Maria authenticates on her iPad
And the iPad has an eligible push destination

When the iPad destination is registered

Then Maria may have two active Push Registrations
And the iPhone registration remains active
And the iPad does not replace the iPhone merely because it was registered later

---

### Scenario: Push notification is delivered to multiple devices

Given Maria has an eligible iPhone Push Registration
And Maria has an eligible iPad Push Registration
And Luna's Appointment validly produces a push notification for Maria

When delivery is attempted

Then the notification may be attempted for both eligible destinations
And the two technical deliveries represent the same User notification context

---

### Scenario: One device rejects notifications

Given Maria has an eligible iPhone destination
And Maria's iPad cannot currently receive push notifications

When a notification for Maria is dispatched

Then the iPhone may still receive a delivery attempt
And the iPad limitation does not invalidate the iPhone destination

---

### Scenario: User has no Push Registration

Given Carlos is a valid User
And Carlos has no eligible Push Registration

When a domain event produces a possible push notification for Carlos

Then no push destination is available
And the originating domain state remains unchanged
And Carlos remains a valid User

---

### Scenario: Appointment confirmation push does not confirm Appointment

Given Luna's Appointment validly becomes `CONFIRMED`

When Maria receives a push informing her of the confirmation

Then the push reflects the existing Appointment state
And the push itself did not perform the confirmation

---

### Scenario: Push delivery fails after Appointment confirmation

Given Luna's Appointment is `CONFIRMED`
And a push notification is attempted for Maria
And the provider rejects Maria's iPhone destination

When delivery fails

Then Luna remains `CONFIRMED`
And communication failure does not rollback the Appointment
And other eligible communication destinations remain independent

---

### Scenario: Push does not imply that User read Appointment update

Given a confirmation push is technically accepted by the provider

When Maria does not open the notification

Then the system must not infer that Maria read or acknowledged the Appointment
solely from provider acceptance

---

### Scenario: Reschedule push does not accept proposal

Given Animalia proposes a confirmed Appointment reschedule
And Maria receives a push describing the proposal

When the push is delivered

Then the Appointment is not considered rescheduled solely because of the push
And Maria must explicitly accept through the applicable Appointment workflow

---

### Scenario: User signs out on one device

Given Maria is authenticated on iPhone and iPad
And both devices have Push Registrations

When Maria signs out on the iPhone

Then the iPhone must no longer remain eligible for Maria's private push
notifications through that signed-out context
And the iPad may remain eligible
And Maria's User-level domain relationships remain unchanged

---

### Scenario: Another User uses former device

Given Maria previously used an iPhone
And Maria signed out
And Carlos later authenticates on that same iPhone

When the push destination is established for Carlos

Then Carlos's private notifications may use the applicable destination
And Maria's private notifications must not continue being delivered through
Carlos's current device context

---

### Scenario: Provider token rotates

Given Maria has an existing active Push Registration
And the push provider issues a replacement destination token for the same
applicable device context

When the registration is refreshed

Then the technical destination may be updated
And Maria remains the same domain User
And another Guardian or Membership is not created

---

### Scenario: Provider declares token invalid

Given Maria has an old Push Registration
And trusted provider feedback establishes that its destination is invalid

When the provider event is processed

Then that registration no longer remains normally eligible for future push
delivery
And Maria's other valid registrations remain unaffected

---

### Scenario: Account recovery protects lost device

Given Maria has an authenticated lost phone with an active Push Registration
And Maria successfully completes account recovery
And previous authentication sessions are invalidated

When future private notifications are evaluated

Then the lost phone's obsolete authenticated context must not continue
receiving Maria's private notifications
And a valid notification context must be re-established where necessary

---

### Scenario: Medical push minimizes information

Given Luna has a new protected clinical update
And Maria is authorized to access the applicable information inside the
application

When a push is generated

Then the push does not need to contain detailed medical information
And Maria may be directed to the authenticated application to view the
protected content

---

### Scenario: Deep link does not bypass authorization

Given Maria receives a push containing navigation information for Luna
And Maria's relevant authorization later ends

When Maria opens the old notification

Then current authentication and authorization are evaluated
And the notification reference does not create permanent access

---

### Scenario: Old Appointment push opens current state

Given Maria received an Appointment confirmation push
And the Appointment was subsequently cancelled

When Maria later opens the old confirmation notification

Then the application displays the current authoritative Appointment state
And the stale push payload does not restore `CONFIRMED`

---

### Scenario: Duplicate provider callback is harmless

Given a provider delivery callback has already been processed

When the same callback is delivered again

Then no duplicate domain operation occurs
And notification-delivery state remains coherent

---

## 7. User Preference vs Device Capability

The product must preserve this distinction:

    User preference
    "I want Appointment notifications"

            ≠

    Device capability
    "This iPhone can currently receive push"

A User may therefore have:

    preference enabled
        +
    zero eligible devices

or:

    preference enabled
        +
    two eligible devices

or:

    preference disabled
        +
    technically valid device registration

The final delivery decision may depend on both product policy and device
eligibility.

---

## 8. Push Notification vs Authoritative State

Push is a hint that something happened.

The application remains authoritative.

Conceptually:

    domain state changes
          ↓
    push notification
          ↓
    User opens application
          ↓
    current trusted domain state is loaded

not:

    User opens notification
          ↓
    notification payload becomes domain truth

---

## 9. Privacy Boundary

Push notifications may be visible without unlocking the device.

Therefore:

    lock-screen notification
        ≠
    secure authenticated application view

Sensitive medical or personal details should remain inside the protected
application where authorization can be evaluated.

A push should normally communicate that something requires attention rather
than reproduce the protected content itself.

---

## 10. Sign Out and Push Registration

Signing out ends authenticated use of the applicable client context.

It must also prevent that signed-out context from continuing to receive private
notifications for that User.

Conceptually:

    Maria
    iPhone
    authenticated
        +
    Push Registration A

        ↓ sign out

    iPhone session ended

        ↓

    Push Registration A
    no longer eligible for Maria's private notifications

Other independent Maria device contexts may remain active.

---

## 11. Edge Cases

### Operating-system permission is changed outside the app

A User may disable push permission through device settings.

The application may not learn this immediately.

Provider or device feedback may later make the registration ineligible.

The originating domain state remains unaffected.

---

### Application is reinstalled

Reinstallation may result in a new provider destination token.

The system must not assume that the previous token remains valid indefinitely.

---

### Same physical device changes User

Push delivery must follow the currently valid User association rather than the
physical device alone.

---

### User owns many devices

Phase 1 does not require an arbitrary product limit on the number of valid
Push Registrations.

Operational anti-abuse limits may be introduced architecturally if necessary.

---

### Notification arrives significantly late

The notification may no longer describe current domain state.

Opening it must retrieve the current authoritative state.

---

### Push provider is unavailable

Push may fail or remain pending.

The underlying Appointment, Invitation, or other domain event remains valid
according to its own lifecycle.

---

## 12. Relevant Invariants

- **INV-001 — One User may have multiple capabilities.**
- **INV-003 — Multiple Guardians are supported.**
- **INV-006 — Organization Membership is temporal.**
- **INV-009 — Historical clinical provenance is immutable.**
- **INV-013 — Subscription termination does not erase history.**
- **INV-015 — Private operations require an authenticated identity.**

---

## 13. Dependencies

- SPEC-ID-003 — Authenticate User
- SPEC-ID-004 — Sign Out
- SPEC-ID-005 — Recover Account Access
- SPEC-COM-001 — Send Transactional Email

Appointment-specific notification recipient and event behavior is defined by:

- SPEC-COM-003 — Send Appointment Notifications

---

## 14. Out of Scope

This Specification does not define:

- push notification provider selection;
- APNs implementation;
- Firebase Cloud Messaging implementation;
- exact Push Registration table structure;
- physical device identity;
- device-management UI;
- notification preference UI;
- exact notification categories;
- marketing push;
- notification sounds;
- badges;
- notification grouping;
- exact retry strategy;
- delivery guarantees;
- read receipts;
- acknowledgement tracking;
- remote wipe;
- mobile-device management;
- Appointment-specific recipient policy.

---

## 15. Verification Notes

Verification must demonstrate that:

1. one User may have zero, one, or multiple Push Registrations;
2. registering a second device does not require replacing an unrelated active
   first device;
3. a Push Registration is not domain User identity or authentication proof;
4. User notification preference and device capability remain distinct;
5. one logical notification may be attempted across several eligible User
   destinations;
6. multiple technical deliveries do not duplicate domain meaning;
7. invalidating one destination does not invalidate another valid destination;
8. provider token rotation does not change domain User identity;
9. sign out makes the applicable device context ineligible for future private
   notifications for that User;
10. signing out one device does not necessarily disable another independently
    authenticated device;
11. a device later used by another User must not continue receiving the former
    User's private notifications;
12. account recovery prevents obsolete authenticated contexts from continuing
    private push delivery;
13. push submission, provider acceptance, delivery, display, and User
    acknowledgement are not treated as equivalent events;
14. failed push delivery does not rollback the originating domain operation;
15. push payloads minimize sensitive information;
16. detailed protected medical information is not ordinarily exposed through
    push payloads;
17. deep links do not bypass current authentication or authorization;
18. stale notifications do not override current domain state;
19. manipulated clients cannot fabricate authoritative notification events;
20. provider callbacks cannot independently modify domain state;
21. duplicate provider callbacks are idempotent;
22. Push Registration lifecycle does not modify User domain relationships;
23. absence of push capability does not make the User invalid.
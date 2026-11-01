# Veterinary Care Platform

**Status:** Draft
**Version:** 0.2
**Project type:** Long-lived SaaS product / Master's Final Project initial delivery
**Development approach:** Spec-Driven Development

## 1. Project Vision

Build a veterinary care platform that connects pet guardians with veterinary clinics while providing a longitudinal medical history for each pet across participating veterinary organizations.

The platform is intended to become a real, maintainable SaaS product.

The Master's Final Project represents the first major delivery phase of the product, not the lifetime scope of the system.

The product will be developed using a **Spec-Driven Development (SDD)** approach, where explicit requirements and specifications drive domain modeling, architectural decisions, implementation, and verification.

The expected development flow is:

```text
Business need
    ↓
Requirement
    ↓
Specification
    ↓
Acceptance scenarios
    ↓
Domain impact
    ↓
Architectural / data impact
    ↓
Implementation
    ↓
Automated verification
```

Specifications are the functional source of truth.

---

## 2. Problem Statement

Veterinary information is commonly fragmented across individual veterinary centers.

When a pet receives care from different clinics over time, its medical information may become distributed across multiple independent systems.

This can lead to:

* incomplete medical context during consultations;
* manual transfer of medical information between clinics;
* duplicated tests or procedures;
* difficulty for guardians to maintain a complete view of their pet's health;
* loss of context when veterinarians or guardians change clinics;
* limited continuity of care.

At the same time, pet guardians may find it difficult to discover nearby veterinary clinics, compare their services, and interact with them through a consistent digital experience.

The platform aims to address both problems:

1. make veterinary clinics discoverable and accessible to pet guardians;
2. provide a longitudinal, traceable medical history centered around the pet.

---

## 3. Core Product Statement

> A SaaS veterinary care platform that allows pet guardians to discover clinics, manage their pets and appointments, and maintain a longitudinal veterinary history while preserving the origin, authorship, clinical context, and access rules of medical information across different veterinary organizations.

---

## 4. Product Principles

### 4.1 The pet is the center of the medical history

Medical history is conceptually associated with the Pet rather than with the Clinic that currently treats it.

A Pet may receive care from many Clinics during its lifetime.

Each clinical event must preserve its original context.

---

### 4.2 Identity is independent from capabilities

A User represents a person.

A User may simultaneously:

* be guardian of one or more Pets;
* be a Veterinarian;
* work for one or more veterinary Organizations;
* administer an Organization;
* perform different responsibilities in different contexts.

The system must not model these capabilities as mutually exclusive user types.

---

### 4.3 Organizations and physical clinics are different concepts

The commercial customer of the platform is a veterinary **Organization**.

An Organization may operate one or more physical **Clinics**.

Example:

```text
Veterinary Group Animalia
├── Animalia Madrid Centro
├── Animalia Alcobendas
└── Animalia Getafe
```

This distinction must exist conceptually even if the first product phase mainly exercises single-clinic organizations.

The system must not assume that one paying customer always corresponds to exactly one physical location.

---

### 4.4 Professional relationships are contextual and temporal

A professional relationship with a veterinary Organization or Clinic changes over time.

The platform must preserve:

* when a professional relationship started;
* when it ended;
* the context in which historical actions were performed.

Current employment must never rewrite historical clinical attribution.

---

### 4.5 Historical clinical truth must be preserved

Medical information represents historical clinical facts.

Once a clinical record has been finalized, it should not be silently rewritten in a way that destroys its previous meaning.

Corrections, amendments, authorship, timestamps, and provenance must be explicitly representable.

The exact clinical record lifecycle will be defined through specifications.

---

### 4.6 Professional qualification does not imply medical access

Being a registered Veterinarian does not grant access to every Pet in the system.

Medical access must be derived from explicit authorization rules and professional context.

---

### 4.7 Least privilege by default

Users, professionals, Organizations, and Clinics should only receive the minimum access necessary for the operation they are allowed to perform.

Authorization is a domain concern, not merely a user-interface concern.

---

### 4.8 Specifications drive implementation

Functionality must not be implemented simply because it appears useful.

Relevant behavior must be supported by:

* an explicit requirement;
* a specification;
* or an architectural decision required to support existing specifications.

Future capabilities should influence architectural boundaries when reasonably foreseeable, but should not be implemented before they are required.

---

### 4.9 Build for evolution, not speculation

The platform should avoid both extremes:

* disposable designs that only work for the first delivery;
* speculative abstractions for hypothetical future features.

The preferred approach is:

> Implement what is required today while preserving architectural boundaries that make likely future evolution possible.

---

## 5. Main Actors

### 5.1 Anonymous Visitor

A person using the platform without authentication.

May:

* discover nearby Clinics;
* view public Clinic information;
* view public services and characteristics;
* use geographic discovery.

May not:

* register Pets;
* book Appointments;
* access private customer information;
* access medical information.

---

### 5.2 User

A person with an identity in the platform.

A User is the foundation upon which additional domain relationships are established.

A User is not inherently a Guardian, Veterinarian, or Administrator.

---

### 5.3 Pet Guardian

A User with a recognized responsibility relationship with a Pet.

A Pet may have multiple Guardians.

Guardian permissions may differ depending on the relationship and future specifications.

---

### 5.4 Veterinarian

A User with a recognized veterinary professional identity.

A Veterinarian may practice in one or more Clinics and may simultaneously be a Pet Guardian.

---

### 5.5 Organization Member

A User with an active professional relationship with a veterinary Organization.

Responsibilities may include, among others:

* Organization owner;
* administrator;
* Veterinarian;
* receptionist.

Responsibilities may be Organization-wide or scoped to specific Clinics.

The exact authorization model will be specification-driven.

---

### 5.6 Veterinary Organization

The business entity that uses the professional platform and owns the commercial subscription.

An Organization may:

* operate one or more Clinics;
* have multiple members;
* manage professional access;
* subscribe to the platform;
* configure business information.

A Veterinary Organization becomes a platform customer through trusted
commercial onboarding, which establishes the Organization, its initial Owner,
and its initial Subscription together. A User may request that onboarding from
the application; the User cannot establish an Organization directly.

---

### 5.7 Clinic

A physical veterinary care location belonging to an Organization.

A Clinic may have:

* geographic location;
* public profile;
* opening hours;
* services;
* Veterinarians;
* appointment availability;
* clinical activity.

Clinics are the primary entities shown in geographic discovery.

---

## 6. Value Proposition

### 6.1 For Pet Guardians

The platform aims to provide:

* discovery of nearby veterinary Clinics;
* public information before registration;
* management of multiple Pets;
* appointment booking;
* a longitudinal veterinary history;
* visibility into which professional and Clinic performed each clinical action;
* improved continuity of care between veterinary providers;
* controlled sharing of medical information.

---

### 6.2 For Veterinary Organizations

The platform aims to provide:

* public visibility for their Clinics;
* management of professional teams;
* appointment workflows;
* longitudinal clinical context for authorized Pets;
* creation of traceable medical records;
* multi-Clinic evolution;
* centralized SaaS subscription;
* a digital relationship with Pet Guardians.

---

## 7. Business Model

The product follows a **B2B SaaS** model.

### Pet Guardians

Core Guardian functionality is free.

Users are not required to authenticate to discover public Clinics.

Authentication is required for private operations such as:

* managing Pets;
* booking Appointments;
* managing authorizations;
* viewing medical information.

### Veterinary Organizations

Veterinary Organizations are the paying customers.

A subscription belongs to the Organization rather than to an individual Veterinarian or physical Clinic.

An Organization subscription may cover multiple members and, depending on the commercial plan, potentially multiple Clinics.

Pricing, limits, trial rules, and plan structure will be defined separately.

Phase 1 commercial onboarding and activation may be performed through a trusted
external, web, or manual process. Members invited into an existing Organization
join without their own commercial relationship.

---

## 8. Product Delivery Strategy

The product will evolve through incremental delivery phases.

The Master's Final Project will implement **Phase 1**, which must establish the core product architecture and demonstrate meaningful end-to-end workflows.

Phase 1 must be production-minded, but it is not expected to contain every future capability of the product.

---

## 9. Phase 1 Scope

### 9.1 Identity and Authentication

Phase 1 should support:

* account registration;
* sign in;
* sign out;
* account recovery when required;
* basic user identity management.

Authentication identifiers must not be conflated with domain capabilities.

---

### 9.2 Veterinary Organizations

Phase 1 should support:

* establishing a veterinary Organization through trusted commercial onboarding
  (not open self-service), together with its initial Owner and initial
  Subscription;
* allowing a User to request that commercial onboarding from the application;
* Organization membership;
* administrative responsibilities;
* historical professional relationships.

The model must allow future Organizations with multiple Clinics.

---

### 9.3 Clinics

Phase 1 should support:

* one or more Clinics associated with an Organization;
* public Clinic information;
* physical location;
* Clinic services where required;
* professional assignment to Clinics.

---

### 9.4 Public Clinic Discovery

Anonymous Visitors should be able to:

* discover Clinics geographically;
* view Clinics on a map;
* inspect public Clinic profiles.

Clinic discovery operates on Clinics registered within the platform.

---

### 9.5 Pets and Guardianship

Phase 1 should support:

* Pet registration;
* one User managing multiple Pets;
* a Pet having more than one Guardian at domain level;
* Pet identity independently from any Clinic.

The exact permission differences between multiple Guardians will be specification-driven.

---

### 9.6 Veterinary Professionals

Phase 1 should support:

* veterinary professional profiles;
* professional identification;
* association with Organizations;
* assignment to one or more Clinics;
* start and end of professional relationships;
* preservation of historical professional context.

---

### 9.7 Appointments

Phase 1 should support:

* requesting or booking an Appointment;
* associating it with a Pet;
* associating it with a Clinic;
* optionally associating it with a specific Veterinarian;
* lifecycle state transitions;
* consultation of relevant Appointments.

Appointment behavior must be driven by explicit specifications.

---

### 9.8 Medical Records

Phase 1 should establish the longitudinal medical record model.

Clinical records must preserve:

* the Pet;
* the event date;
* the responsible Veterinarian when applicable;
* the Clinic;
* the Organization context where relevant;
* the type of clinical event;
* clinical information;
* authorship and creation information;
* historical provenance.

The design must support medical events produced by different Clinics over time.

---

### 9.9 Medical Record Integrity

Phase 1 should distinguish between draft and finalized clinical information if required by the specifications.

The system must be capable of preserving corrections and amendments without silently destroying clinically relevant historical information.

The exact finalization and amendment workflow will be specified before implementation.

---

### 9.10 Cross-Clinic Medical Access

Phase 1 must demonstrate controlled access to previous medical information produced outside the currently treating Clinic.

Access must not be automatically granted to every Veterinarian.

The authorization model must support:

* explicit access rules;
* revocation where applicable;
* Clinic or professional context;
* auditability where required.

---

### 9.11 Organization Subscription

Phase 1 should represent:

* an Organization subscription;
* subscription status;
* access to professional functionality based on subscription state.

Subscription cancellation must not delete historical medical information.

---

### 9.12 Transactional Communication

Relevant workflows may generate:

* email notifications;
* push notifications;
* appointment reminders.

Communication channels must remain infrastructure concerns and should not own business state.

---

### 9.13 Single Application

Phase 1 delivers one mobile application serving both Guardian and professional
contexts.

There is no separate professional account type. Professional functionality is
presented when the User's derived professional context supports it, and the
same User may remain a Guardian at the same time.

Presentation is never the authorization boundary.

Web administration remains a possible future evolution (§10).

---

## 10. Expected Future Evolution

The architecture should not prevent reasonable evolution toward capabilities such as:

* Organizations with multiple Clinics;
* richer professional roles;
* advanced scheduling;
* laboratory results;
* diagnostic imaging;
* prescriptions;
* treatment plans;
* vaccination schedules;
* external document attachments;
* audit logs;
* more sophisticated Guardian permissions;
* Clinic teams;
* richer subscription plans;
* web administration;
* iOS distribution;
* integration with external veterinary systems.

These capabilities are **not automatically part of Phase 1**.

They exist here to identify plausible architectural evolution, not to authorize implementation.

---

## 11. Explicit Non-Goals for Phase 1

Unless required by a future approved specification, Phase 1 does not need to implement:

* AI diagnosis;
* automated medical recommendations;
* telemedicine;
* real-time customer chat;
* insurance integrations;
* full accounting;
* payroll;
* advanced inventory;
* pharmacy commerce;
* complete hospital management;
* laboratory-provider integrations;
* regulatory electronic prescription systems;
* marketplace functionality.

These may become future product capabilities without being part of the initial implementation.

---

## 12. Initial Technical Direction

The current intended technology stack is:

* **TypeScript**
* **React Native**
* **Expo**
* **Expo Router**
* **Supabase**
* **PostgreSQL**
* **PostGIS**
* **Supabase Auth**
* **PostgreSQL Row Level Security**
* **Supabase Storage**
* **Supabase Edge Functions**
* **Google Maps**
* **Resend**
* **Cloudflare**
* **Expo Notifications / Firebase Cloud Messaging**
* **Stripe**
* **EAS Build**
* **Google Play**
* **GitHub**
* **GitHub Actions**

Technology choices remain subject to architectural review.

A technology must not be introduced merely because it appears on this list.

It should be added when an actual product, security, operational, or development requirement justifies it.

---

## 13. Development Principles

### 13.1 Vertical delivery

Features should preferably be implemented as complete vertical slices.

Example:

```text
Specification
    ↓
Domain change
    ↓
Database / authorization
    ↓
Application behavior
    ↓
UI
    ↓
Tests
```

The platform should remain in a coherent working state as capabilities are added.

---

### 13.2 Small specifications

Specifications should describe focused behavior.

Large feature descriptions should be decomposed into independently understandable and verifiable specifications.

---

### 13.3 No speculative implementation

Developers and AI agents must not implement future features unless they are necessary to satisfy current approved requirements.

---

### 13.4 No disposable shortcuts in core domain decisions

A Phase 1 simplification must not deliberately corrupt core concepts merely to reduce initial implementation effort.

For example:

* Veterinarians must not be tied permanently to one Clinic.
* Pets must not be permanently tied to one Guardian if multiple Guardians are a known domain requirement.
* Organizations must not be modeled as a single physical Clinic.
* historical medical provenance must not depend on current employment relationships.

---

## 14. AI-Assisted Development

AI coding agents may be used for implementation, review, testing, documentation, and analysis.

AI agents are not the source of truth.

They must follow:

1. approved requirements;
2. specifications;
3. domain rules;
4. architectural decisions;
5. repository conventions.

Agents must not silently resolve domain ambiguity by inventing behavior.

When an unresolved decision affects implementation, it should be surfaced as a domain or architectural question.

---

## 15. Traceability

Relevant behavior should be traceable through the development process.

Example:

```text
REQ-MED-004
    ↓
SPEC-MED-012
    ↓
ADR-006
    ↓
Database migration
RLS policy
Application code
    ↓
Integration test
E2E test
```

Not every change requires every artifact.

The objective is to preserve a clear relationship between business intent and executable behavior.

---

## 16. Success Criteria

The project is successful when it demonstrates both a valuable product foundation and a disciplined SDD process.

Success includes:

* a coherent domain model;
* explicit functional requirements;
* verifiable specifications;
* traceability from specification to implementation;
* meaningful authorization rules;
* historical medical provenance;
* incremental vertical delivery;
* automated tests derived from expected behavior;
* controlled use of AI coding agents;
* a functional Phase 1 product;
* an architecture capable of reasonable future evolution without redesigning the core domain.

The Master's Final Project should demonstrate the process.

The repository should remain suitable for continuing the product afterwards.

# Agent Instructions

This project follows a **Specification-Driven Development (SDD)** approach.

Before making any change, read this document in full.

## 1. Sources of Truth

Product and technical decisions are defined by the repository documentation.

Relevant sources include:

- [docs/PROJECT.md](docs/PROJECT.md) — product vision, scope, and product rules.
- [docs/DOMAIN.md](docs/DOMAIN.md) — ubiquitous language, domain concepts, and invariants.
- [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) — product requirements.
- [specs/](specs/) — functional Specifications organized by domain.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — current high-level system architecture.
- [docs/RELATIONAL_MODEL.md](docs/RELATIONAL_MODEL.md) — approved detailed Phase 1 relational-design baseline.
- [docs/IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) — current operational implementation checkpoint.
- [docs/CONVENTIONS.md](docs/CONVENTIONS.md) — repository-wide engineering conventions.
- [docs/TESTING.md](docs/TESTING.md) — automated verification strategy.
- [docs/decisions/](docs/decisions/) — accepted Architecture Decision Records.

When repository artifacts appear to disagree, follow the precedence defined in
`docs/CONVENTIONS.md`.

Do not silently resolve documentation conflicts.

Report the conflict before implementing behavior whose intended meaning is
unclear.

---

## 2. Specification-Driven Development

Do not implement product behavior that is not supported by an existing approved
Specification under [specs/](specs/).

If a requested behavior is not covered by an approved Specification:

1. do not implement it;
2. identify the missing or incomplete Specification;
3. report the gap instead of inventing behavior;
4. a Specification may be proposed separately, but implementation must not
   precede the approved behavior.

Specifications marked `PROPOSED` must not be treated as approved product
behavior unless the task explicitly concerns reviewing or completing that
Specification.

Behavior marked for a later delivery phase must not be implemented during
Phase 1 unless explicitly requested and the governing documentation is updated.

---

## 3. Before Implementing a Change

Before starting implementation work, inspect `docs/IMPLEMENTATION_STATUS.md`
and the current migrations to establish the repository's actual implementation
boundary. Prior chats or agent outputs are not a substitute for repository
inspection.

Before modifying source code, database schema, migrations, authorization,
architecture, or tests:

1. identify the Requirement or Requirements involved;
2. identify the approved Specification or Specifications involved;
3. read the relevant sections of `docs/DOMAIN.md`;
4. read applicable architectural constraints in `docs/ARCHITECTURE.md`;
5. read `docs/RELATIONAL_MODEL.md` before proposing or modifying database
   schema, migrations, or persistence structures;
6. read applicable repository rules in `docs/CONVENTIONS.md`;
7. read applicable accepted ADRs;
8. read `docs/TESTING.md` when verification is involved.

Do not rely only on the task description when repository documentation contains
more precise behavior.

---

## 4. Domain Model

Use terminology defined in `docs/DOMAIN.md` and approved Specifications.

Do not:

- introduce synonyms for established domain concepts;
- collapse distinct domain concepts for implementation convenience;
- make provider-specific identifiers primary domain identities;
- redesign domain relationships to match a particular UI;
- infer current authorization from historical relationships;
- infer historical truth from mutable current state.

Preserve distinctions established by the domain model, including where
applicable:

- User vs authentication identity;
- Veterinary Organization vs Clinic;
- Organization Membership vs Clinic Assignment;
- Pet vs Guardianship;
- Appointment lifecycle vs clinical documentation (Clinical Record Entries of
  the Appointment);
- Appointment Veterinarian Assignment (who may record new documentation now)
  vs clinical authorship (who recorded each Entry, fixed forever);
- prior-history access (Care Authorization) vs Appointment documentation
  access;
- Subscription vs Entitlement;
- Clinic Opening Hours vs Appointment Availability;
- Clinic Service vs Clinical Event type;
- current relationship vs historical relationship.

If implementation pressure appears to require collapsing two documented
concepts, stop and report the conflict instead.

---

## 5. Historical Integrity

Historical information required to interpret business or clinical events must
not be destructively rewritten merely because current relationships change.

Preserve historical information such as:

- Organization Membership periods;
- Clinic Assignment periods;
- Appointment lifecycle history;
- Veterinarian Assignment history;
- the Appointment context of Clinical Record Entries;
- recorded clinical authorship;
- Clinic and Organization clinical provenance;
- Clinical Amendments;
- medical-access audit information;
- Subscription history where required.

Ordinary lifecycle changes must not erase historical medical information.

---

## 6. Persistence Design

Do not create a persistent entity merely because it appears convenient for the
implementation.

Before proposing a persistent concept, identify:

- the approved Specification or architectural requirement that justifies it;
- its domain purpose;
- relationships and cardinalities;
- whether it is current, temporal, or historical;
- whether it is mutable or historically preserved;
- candidate integrity constraints;
- authorization-sensitive relationships;
- whether the value should instead be derived.

Do not persist derived information unnecessarily when it can be reliably
computed from authoritative domain state.

External-provider identifiers may be stored as integration references where
required, but they must not replace stable domain identity.

---

## 7. Database Changes

All schema changes must follow the migration rules defined in
`docs/CONVENTIONS.md`.

Do not:

- modify shared or production schemas manually;
- create migrations for speculative future behavior;
- weaken domain integrity to simplify implementation;
- perform destructive schema changes without considering existing historical
  data;
- create migrations before the proposed persistence model for the relevant
  domain has been reviewed.

When proposing database constraints, distinguish between:

- rules safely enforceable through relational constraints;
- lifecycle rules requiring trusted domain operations;
- authorization rules requiring trusted access-control boundaries.

---

## 8. Security and Authorization

The mobile client is not the security boundary.

Client-side checks may improve user experience but must not be relied upon to
protect domain operations or sensitive information.

Protected behavior must be enforceable through trusted backend or data-access
boundaries.

Preserve the distinction between:

- authentication;
- Organization capability;
- Clinic context;
- Guardianship;
- professional authorization;
- Subscription Entitlement;
- Medical Access Control.

Never assume that:

- authentication alone grants domain capability;
- Organization Membership alone grants every Organization capability;
- Veterinarian status grants arbitrary medical access;
- Subscription existence grants every paid capability;
- client-provided state is authoritative.

Privileged secrets and service credentials must never be embedded in
distributable client code or committed to source control.

---

## 9. Medical Information

Protected medical information requires explicit authorization.

Do not weaken Medical Access Control for implementation convenience.

Clinical history must preserve:

- Pet identity;
- clinical context;
- responsible professional context;
- Clinic;
- Veterinary Organization where applicable;
- authorship;
- historical provenance.

Recorded (finalized) clinical information must not be silently destructively
rewritten.

Clinical corrections must follow the applicable Amendment behavior.

---

## 10. Scope Discipline

Implement the smallest coherent change that satisfies the approved
Specification.

Do not:

- implement unrelated future functionality;
- perform unrelated refactors;
- introduce speculative abstractions;
- add dependencies without a concrete need;
- redesign unrelated domain areas;
- modify Requirements or Specifications merely to make an implementation pass.

Refactoring is allowed when necessary to implement the requested behavior
safely or when performed as an explicit standalone task.

---

## 11. Dependencies and Infrastructure

Do not add a dependency, framework, external service, database extension, or
infrastructure component without a concrete documented need.

When a technical choice:

- has meaningful alternatives;
- affects long-term architecture;
- introduces significant coupling;
- or would be difficult to reverse;

identify whether an ADR should be created before or as part of the change.

Do not create ADRs for routine implementation details.

---

## 12. Testing

Automated verification follows `docs/TESTING.md`.

Approved Specification Verification Notes are the primary source for behavioral
test design.

When implementing behavior:

- add or update automated verification where applicable;
- test observable behavior rather than implementation details;
- include negative authorization cases for protected operations;
- verify important lifecycle transitions;
- verify historical integrity where applicable;
- verify relevant domain invariants.

Do not modify product behavior merely to satisfy an existing test.

If a test conflicts with an approved Specification, report the conflict.

---

## 13. AI-Assisted Changes

AI coding agents must:

1. read the relevant repository documentation before implementation;
2. identify the Requirement and Specification being addressed;
3. respect established domain terminology;
4. keep changes within the requested scope;
5. report missing or contradictory business rules instead of inventing them;
6. avoid adding dependencies without justification;
7. preserve historical and authorization boundaries;
8. add or update automated verification where applicable;
9. run applicable validation and tests after changes;
10. summarize significant changes and unresolved concerns.

Agents must not modify Requirements, Specifications, domain invariants, or ADRs
merely to make an implementation easier.

---

## 14. Analysis-Only Tasks

When explicitly asked to analyze, review, derive, or propose a design without
making changes:

- do not modify repository files;
- do not create migrations;
- do not create implementation code;
- distinguish documented facts from inferred design proposals;
- cite the Requirements, Specifications, invariants, or ADRs that justify each
  important conclusion;
- flag uncertainty instead of guessing.

A request to derive a persistence model is not permission to implement that
model.

---

## 15. Working Style

Prefer small, reviewable changes.

Before making a significant architectural change, explain:

- what problem requires the change;
- which approved Requirements or Specifications justify it;
- what alternatives exist;
- why the proposed approach fits the current architecture;
- whether an ADR is warranted.

When a task cannot be completed without inventing product behavior, stop at the
documented boundary and report what is missing.

---

## 16. Unified Repository Layout and Command Boundaries

This repository contains both the authoritative backend/domain implementation and
the MenizVet mobile client.

Repository areas have distinct responsibilities:

- `docs/`, `specs/`, and `supabase/` define and implement authoritative product,
  domain, persistence, authorization, and backend behavior.
- `apps/mobile/` contains the Expo/React Native client implementation.
- Mobile code must consume and present approved backend/domain behavior; it must
  not invent, redefine, or bypass Requirements, Specifications, domain
  invariants, authorization rules, or backend contracts.

When a mobile requirement appears to require new or changed domain behavior,
inspect the authoritative repository sources before implementing it. If the
required behavior is not approved there, report the gap rather than encoding a
client-only rule.

Command working directories are intentionally separate:

- run Supabase/backend repository commands from the repository root;
- run npm, Expo, TypeScript, and EAS commands from `apps/mobile/`.

Examples:

- repository root: `npx supabase ...`
- `apps/mobile/`: `npm ...`, `npx expo ...`, `npx eas-cli ...`

Do not add root-level JavaScript package-management or monorepo orchestration
solely because the mobile application lives in this repository. In particular,
do not introduce workspaces, Nx, Turborepo, shared packages, or generated client
layers without a concrete approved need.

Local/generated files such as `.env.local`, `.expo/`, `node_modules/`,
`expo-env.d.ts`, `supabase/.temp/`, and local AI/editor settings must remain
untracked according to the repository ignore rules.

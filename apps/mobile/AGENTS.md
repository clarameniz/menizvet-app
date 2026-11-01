# Mobile Agent Instructions

Before modifying anything under `apps/mobile/`:

1. read and follow the repository-root `AGENTS.md`;
2. treat the repository-root product/domain/backend documentation as
   authoritative;
3. do not invent client-side domain, authorization, subscription, scheduling,
   clinical, communications, or discovery behavior that is not supported by the
   approved repository sources.

# Expo HAS CHANGED

Read the exact versioned docs at
https://docs.expo.dev/versions/v57.0.0/
before writing Expo-specific code.

Run mobile commands from `apps/mobile/`, including:

- `npm ...`
- `npx tsc ...`
- `npx expo ...`
- `npx eas-cli ...`

Do not run Supabase repository commands from this directory; run them from the
repository root.

# Mobile Engineering Standards

Established by the Mobile Production Foundation Hardening pass. These are
durable rules, not a tutorial — apply them in every future implementation
pass.

## Architecture

- Directory shape and dependency direction are fixed:
  `app/` (routes/screens) → `components/`, `data/`, `lib/`, `i18n/`, `hooks/`,
  `constants/`. Lower layers must never import from `app/`.
- All Supabase table/RPC/Edge Function calls live in `src/data/<resource>.ts`
  — never inline in a route component. `src/data/user-profile.ts` is the
  reference pattern.
- Route components primarily orchestrate: navigation, screen-local state,
  calls into `src/data`, and composition of reusable UI. They must not
  contain direct Supabase calls.
- Do not introduce repository classes, use-case classes, DI containers,
  generic service layers, Clean Architecture/DDD layers, Redux/Zustand/React
  Query, or Nx/Turborepo/workspaces. The `route → data/*.ts → supabase` chain
  is the intended shape until a concrete need proves otherwise.

## Component and hook design

- Components should be small and cohesive; there is no arbitrary line-count
  limit. Split a component when it mixes independent responsibilities
  (backend access, complex state transitions, navigation, data
  transformation, several unrelated UI sections) — not to hit a line count.
- Do not extract a component merely to shorten a file. Extract when it is
  reused, represents a coherent UI concept, materially simplifies a screen,
  or owns a distinct behavior.
- Custom hooks are for genuine reusable or sufficiently complex
  React-specific behavior (lifecycle, subscriptions, stateful
  orchestration). Do not create a hook just to move plain functions out of a
  component; logic with no React state/lifecycle dependency stays a plain
  function/module. Do not add speculative generic hooks (`useAsync`,
  `useApi`, `useForm`, ...) without repeated concrete need. If a third
  AppState/foreground concern appears, consolidate the existing foreground
  listeners into one shared hook — not before.

## React state and effects

- Prefer derived values over duplicated state. Do not use `useEffect` to set
  state that can be computed directly during render.
- Effects exist to synchronize with external systems/lifecycle, not for
  general computation.
- Any async effect that may set state after an `await`/`.then()` completes
  must guard against a stale/unmounted completion (an `isMounted` flag
  checked before every state update in the callback, cleared in the
  effect's cleanup — see `session-provider.tsx`, `locale-provider.tsx`,
  `profile.tsx`, `reset-password.tsx`).
- Don't reach for `useMemo`/`useCallback` mechanically. Use them for stable
  context/provider APIs, meaningful referential stability, demonstrated
  expensive computation, or a dependency that genuinely needs stable
  identity.

## TypeScript

- Keep `strict: true`. Avoid `any`, unsafe casts, and unjustified non-null
  assertions; prefer discriminated unions, explicit nullable types, and
  exhaustive handling of finite states over loosely-typed dictionaries.
- Data-access results use the established discriminated shape:
  `{ data: T; error: null } | { data: null; error: string }`. Do not throw
  ordinary backend/data errors across the UI boundary — make expected
  failure explicit in the return type.
- Data-access functions never accept an arbitrary User ID unless the
  backend contract genuinely requires cross-user targeting, never reproduce
  authorization logic client-side, and always select explicit columns
  (never `select('*')`).

## Localization

- Every new product-facing string is added to both the Spanish and English
  catalogs (`src/i18n/locales/es.ts` / `en.ts`) in the same change. No
  hard-coded user-facing product string in a route or component outside
  explicitly developer-only tooling.
- Catalog key parity is a compile/type validation failure, not a runtime
  concern — `locales/en.ts`'s type is derived from `es.ts`'s exact key
  shape. Runtime fallback (`enableFallback`) is defensive only.

## Error handling and privacy

- Raw Supabase/Postgres/provider errors never reach product UI. A new
  user-visible failure maps to a concrete localized message when the case
  is known (`i18n/error-messages.ts`), or the single generic localized
  fallback otherwise. Do not build a speculative error taxonomy.
- Never log: passwords, access/refresh tokens, recovery codes, full
  Supabase sessions, full email addresses, Push tokens, protected
  medical/clinical content, or sensitive provider/backend response
  payloads. `console.warn`/`console.error` may contain safe operational
  metadata only (e.g. a storage key name, never its value).
- No service-role or other privileged backend credential may ever exist in
  mobile code or mobile config.

## Dependencies and native builds

- Add dependencies only via `npx expo install` (never bare `npm install`
  for anything touching native code), and only for a concrete, current
  need — not speculatively.
- Every pass that adds or removes a native dependency, or changes
  `app.json`/config plugins, must explicitly report whether a new
  development build is required.

## Validation and testing

- `npm run typecheck` (`tsc --noEmit`) and `npm run lint` (`eslint .`) must
  pass before a change is considered done. `npm run format:check` must be
  clean for anything not explicitly excluded in `.prettierignore`.
- Add unit tests (`npm test`, Jest via `jest-expo`) for new pure
  functions/pure mapping logic as they're introduced — the same proportion
  used for `normalizeEmail`, `mapErrorToKey`, `resolveSystemLocale`, and the
  profile row mapper. Do not add component/E2E test infrastructure without
  a concrete, demonstrated need.
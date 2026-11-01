# MenizVet mobile

The MenizVet Expo / React Native client. It consumes the backend and domain
behavior defined at the repository root; it does not define its own.

Read [AGENTS.md](AGENTS.md) (and the repository-root `AGENTS.md`) before
changing anything here.

## Commands

Run every command from `apps/mobile/`.

```bash
npm install          # install dependencies
npx expo start       # start Metro for the development build
npm run typecheck    # tsc --noEmit
npm run lint         # eslint .
npm run format:check # prettier --check .
npm test             # jest
```

The app runs in a development build (`expo-dev-client`), not Expo Go. Any
change to native dependencies or `app.config.ts` plugins needs a new
development build.

## Brand assets

`assets/brand/` holds the MenizVet symbol and lockup SVGs — the source of
truth for the brand mark. The app icon, Android adaptive/monochrome icons and
favicon in `assets/images/` are derived from `assets/brand/logo-symbol*.svg`;
never edit those PNGs by hand. If the mark changes, regenerate them:

```bash
npm install --no-save @resvg/resvg-js@2.6.2   # rasterizer; not a project dependency
node scripts/generate-brand-icons.js
```

New icons only appear after a fresh development build (uninstall the old one
first so launcher icon caches refresh).

## Layout

- `src/app/` — routes (Expo Router file-based routing)
- `src/components/design-system/` — Design System v1 components
- `src/theme/` — Design System v1 tokens (colors, spacing, radius, typography)
- `src/data/` — all Supabase access
- `src/lib/` — pure helpers and app-level utilities
- `src/i18n/` — Spanish/English catalogs and locale handling

import * as Localization from 'expo-localization';
import { I18n } from 'i18n-js';

import { en } from '@/i18n/locales/en';
import { es } from '@/i18n/locales/es';
import type { DotPaths, LocaleCode } from '@/i18n/types';

export type TranslationKey = DotPaths<typeof es>;

export const SUPPORTED_LOCALES: readonly LocaleCode[] = ['es', 'en'];

export const i18n = new I18n({ es, en });
i18n.defaultLocale = 'es';
i18n.locale = 'es';
// Defensive only: with es/en compile-time key parity (see locales/en.ts),
// a key genuinely missing from the active locale shouldn't happen. If it
// ever does anyway, fall back to Spanish text rather than i18n-js's default
// visible "[missing ...]" placeholder. This is not a substitute for catalog
// completeness, which tsc already enforces.
i18n.enableFallback = true;

/**
 * Resolution for the "system" preference: any Spanish device locale (es,
 * es-ES, es-MX, ...) → Spanish; any English device locale (en, en-US, ...)
 * → English; anything else → Spanish fallback. Only the user's single most
 * preferred device locale is considered — not scanned through their whole
 * fallback list — so the result matches what they'd expect from their
 * primary language setting.
 */
export function resolveSystemLocale(): LocaleCode {
  const languageCode = Localization.getLocales()[0]?.languageCode?.toLowerCase();

  if (languageCode === 'es') return 'es';
  if (languageCode === 'en') return 'en';
  return 'es';
}

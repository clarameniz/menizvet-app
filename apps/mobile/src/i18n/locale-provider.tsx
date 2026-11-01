import * as SecureStore from 'expo-secure-store';
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type PropsWithChildren,
} from 'react';
import { AppState } from 'react-native';

import { i18n, resolveSystemLocale, type TranslationKey } from '@/i18n/i18n';
import type { LocaleCode, LocalePreference } from '@/i18n/types';

const PREFERENCE_STORAGE_KEY = 'menizvet.locale-preference';

type LocaleContextValue = {
  /** The actual locale in effect right now — always 'es' or 'en'. */
  locale: LocaleCode;
  /** The user's explicit choice — 'system' is a distinct, persisted state. */
  preference: LocalePreference;
  setPreference: (preference: LocalePreference) => void;
  t: (key: TranslationKey, options?: Record<string, string | number>) => string;
  /**
   * True until the persisted preference has been read from SecureStore at
   * least once. Named to match useSession()'s isLoading so the root layout
   * can combine both into one splash-hide condition. Before this settles,
   * `locale` is provisionally the device locale (resolveSystemLocale() is
   * synchronous, so that part is never wrong) — but a persisted manual
   * override, if any, hasn't been applied yet, so consumers that must not
   * show a momentarily-wrong language should wait for this to be false.
   */
  isLoading: boolean;
};

const LocaleContext = createContext<LocaleContextValue | undefined>(undefined);

function isLocalePreference(value: string | null): value is LocalePreference {
  return value === 'system' || value === 'es' || value === 'en';
}

export function LocaleProvider({ children }: PropsWithChildren) {
  // 'system' is the default until a persisted preference (if any) loads —
  // never store the resolved device locale itself as the preference, or a
  // later OS language change would have nothing to "resume" from.
  const [preference, setPreferenceState] = useState<LocalePreference>('system');
  const [systemLocale, setSystemLocale] = useState<LocaleCode>(resolveSystemLocale());
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let isMounted = true;

    SecureStore.getItemAsync(PREFERENCE_STORAGE_KEY)
      .then((stored) => {
        if (!isMounted) return;
        if (isLocalePreference(stored)) {
          setPreferenceState(stored);
        }
      })
      .catch(() => {
        // Corrupt/unavailable preference storage: stay on 'system' rather
        // than blocking app usage.
      })
      .finally(() => {
        if (isMounted) setIsLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, []);

  // iOS locale is static for the process lifetime; Android can change it
  // from Settings without restarting the app. expo-localization has no
  // change-event API, so its own guidance is to re-resolve on foreground.
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        setSystemLocale(resolveSystemLocale());
      }
    });

    return () => {
      subscription.remove();
    };
  }, []);

  const setPreference = useCallback((next: LocalePreference) => {
    setPreferenceState(next);
    SecureStore.setItemAsync(PREFERENCE_STORAGE_KEY, next).catch(() => {
      // Best-effort: the in-memory preference still applies for this run
      // even if persisting it fails.
    });
  }, []);

  const locale: LocaleCode = preference === 'system' ? systemLocale : preference;

  // i18n-js's instance is a mutable singleton, not React state; setting this
  // synchronously in the render body (rather than in a useEffect) is
  // deliberate so this render's own t() calls already use the correct
  // locale, instead of one render behind. Reviewed against
  // eslint-config-expo's react-hooks/immutability rule (added for this
  // project's reactCompiler: true experiment): a real redesign — computing
  // translated strings without a mutable external instance — is a genuine
  // i18n architecture change and out of scope for this hardening pass, which
  // preserves existing i18n behavior rather than redesigning it. Revisit if
  // this ever causes an observable compiler-memoization bug.
  // eslint-disable-next-line react-hooks/immutability
  i18n.locale = locale;

  // Intentionally depends on `locale` (not read inside the callback body, but
  // via the i18n.locale mutation above) so a locale change produces a new
  // `t` reference and consumers re-render. The linter can't see that
  // indirection, hence the disable — same reviewed exception as above.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const t = useCallback<LocaleContextValue['t']>((key, options) => i18n.t(key, options), [locale]);

  const value = useMemo<LocaleContextValue>(
    () => ({ locale, preference, setPreference, t, isLoading }),
    [locale, preference, setPreference, t, isLoading],
  );

  return <LocaleContext.Provider value={value}>{children}</LocaleContext.Provider>;
}

export function useLocale() {
  const context = useContext(LocaleContext);
  if (context === undefined) {
    throw new Error('useLocale must be used within a LocaleProvider');
  }
  return context;
}

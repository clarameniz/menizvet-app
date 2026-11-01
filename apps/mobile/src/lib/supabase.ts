import 'react-native-url-polyfill/auto';

import { createClient } from '@supabase/supabase-js';
import * as SecureStore from 'expo-secure-store';

const supabaseUrl = process.env.EXPO_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing EXPO_PUBLIC_SUPABASE_URL or EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY. ' +
      'Define both in apps/mobile/.env.local before starting the app.',
  );
}

// expo-secure-store persists session/refresh tokens in the platform keystore
// (Android Keystore / iOS Keychain) rather than plain AsyncStorage.
//
// Storage decision: current Expo SecureStore docs state Expo does not itself
// enforce a value-size limit (the historical ~2048-byte issue was iOS-Keychain
// behavior on some past OS releases, not a fixed or Android-specific cap), and
// this app's session payload (Supabase JWT + refresh token, no large custom
// claims) is far from any value size that has been observed to trip a native
// rejection. Supabase's AsyncStorage+AES "LargeSecureStore" pattern exists for
// apps with large session payloads; it is not adopted here because it isn't
// needed for this Phase 1 session shape and would add a storage dependency
// (AsyncStorage) and a crypto dependency (aes-js) with no concrete benefit
// yet. Revisit only if the persisted value grows (e.g. large custom JWT
// claims) or a real native storage rejection is observed.
//
// Native storage calls are wrapped so a native rejection fails safely: the
// session simply won't persist across restarts rather than crashing or
// silently pretending to have persisted. Never log token/session values here.
const ExpoSecureStoreAdapter = {
  getItem: async (key: string) => {
    try {
      return await SecureStore.getItemAsync(key);
    } catch {
      // Corrupt/incompatible persisted entry (e.g. after a keystore reset or
      // OS restore). Treat as "no session" so the caller falls back to the
      // public route instead of throwing during app bootstrap.
      return null;
    }
  },
  setItem: async (key: string, value: string) => {
    try {
      await SecureStore.setItemAsync(key, value);
    } catch {
      console.warn(
        `[supabase] SecureStore.setItemAsync failed for "${key}"; session will not persist across restarts.`,
      );
    }
  },
  removeItem: async (key: string) => {
    try {
      await SecureStore.deleteItemAsync(key);
    } catch {
      // Best-effort cleanup; nothing sensitive is exposed either way.
    }
  },
};

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: ExpoSecureStoreAdapter,
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
    // Required for the password-recovery deep link (Milestone B): the SDK's
    // default flowType is 'implicit', under which resetPasswordForEmail does
    // not request a PKCE code_challenge, so the recovery email would deliver
    // an implicit-style URL fragment instead of the ?code= param that
    // exchangeCodeForSession expects. 'pkce' is also the flow Supabase's own
    // React Native guidance recommends for native deep links generally.
    flowType: 'pkce',
  },
});

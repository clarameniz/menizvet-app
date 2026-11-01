import { uuid } from 'expo-modules-core';
import * as SecureStore from 'expo-secure-store';

const INSTALLATION_ID_KEY = 'menizvet.pushInstallationId';

/**
 * One random id per app installation, used only so the backend
 * (communications/register-push) can distinguish and rebind Push
 * Registrations per device install (SPEC-COM-002 BR-18,
 * docs/COMMUNICATIONS_BACKEND.md). It is not a secret and carries no
 * authorization weight — the Expo push token and the bound Supabase session
 * remain the real destination/boundary.
 *
 * Uses expo-modules-core's native `uuid.v4()` (its "Core" module's
 * `uuidv4` JSI function — java.util.UUID.randomUUID() on Android,
 * Foundation's UUID() on iOS, both backed by the platform's secure RNG)
 * rather than Math.random. expo-modules-core is already a transitive
 * native dependency of every Expo module this app uses (expo,
 * expo-notifications, expo-constants, ...); this only adds it as an
 * explicit `package.json` dependency for a JS import that was already
 * present, unlinked, in the current development build — it adds no new
 * native code and requires no new EAS build. expo-crypto was
 * deliberately not added: it would be a second native dependency for the
 * exact capability expo-modules-core already provides.
 */
export function generateInstallationId(): string {
  return uuid.v4();
}

/**
 * Generated once when missing and persisted via expo-secure-store (the
 * platform keystore), then reused across every later authenticated session
 * on this installation. Never derived from a User id or push token. A
 * SecureStore write failure still returns a usable in-memory id for the
 * current process rather than failing registration outright — push is a
 * secondary capability (see apps/mobile/AGENTS.md's SecureStore write
 * fallback in lib/supabase.ts for the same rationale).
 */
export async function getInstallationId(): Promise<string> {
  const existing = await SecureStore.getItemAsync(INSTALLATION_ID_KEY);
  if (existing) return existing;

  const generated = generateInstallationId();
  try {
    await SecureStore.setItemAsync(INSTALLATION_ID_KEY, generated);
  } catch {
    console.warn(
      '[installation-id] SecureStore.setItemAsync failed; installation id will not persist across restarts.',
    );
  }
  return generated;
}

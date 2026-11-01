import * as SecureStore from 'expo-secure-store';

import {
  isInvitationId,
  isInvitationSecret,
  type OrganizationInvitationCredential,
} from '@/lib/organization-invitation-link';

/**
 * The one pending Organization Invitation proof (SPEC-ORG-003 §12), kept in the
 * platform keystore while the person signs in, registers, or confirms their
 * email — including across an app restart. Only `{ invitationId, secret }` is
 * stored: Organization, role, address and every other preview fact are always
 * read again from the backend. A newer link replaces an older one.
 *
 * Cleared after every terminal outcome, after "Not now", and on sign-out —
 * never merely because a screen unmounted or an auth screen opened.
 *
 * Failure handling: a corrupt, stale-version or ill-shaped stored value is
 * deleted and treated as absent. If the keystore write fails, the proof is
 * kept in this process's memory only (it will not survive a restart), so the
 * flow still completes now. Never log the value; only the key name.
 */
const PENDING_INVITATION_KEY = 'menizvet.pendingOrganizationInvitation.v1';
const STORED_VERSION = 1;

let unsavedCredential: OrganizationInvitationCredential | null = null;
/** Writes run in order and every read waits for them, so a read never sees an older proof. */
let lastWrite: Promise<void> = Promise.resolve();

function enqueueWrite(write: () => Promise<void>): Promise<void> {
  const next = lastWrite.then(write, write);
  lastWrite = next.catch(() => undefined);
  return next;
}

function parseStored(raw: string): OrganizationInvitationCredential | null {
  try {
    const value: unknown = JSON.parse(raw);
    if (typeof value !== 'object' || value === null || Array.isArray(value)) return null;
    const { version, invitationId, secret } = value as Record<string, unknown>;
    if (
      version !== STORED_VERSION ||
      !isInvitationId(invitationId) ||
      !isInvitationSecret(secret)
    ) {
      return null;
    }
    return { invitationId: invitationId.toLowerCase(), secret };
  } catch {
    return null;
  }
}

async function deleteStored(): Promise<void> {
  try {
    await SecureStore.deleteItemAsync(PENDING_INVITATION_KEY);
  } catch {
    // Best effort; an unreadable value is ignored on the next read anyway.
  }
}

/** Never rejects. */
export function savePendingOrganizationInvitation(
  credential: OrganizationInvitationCredential,
): Promise<void> {
  const value = JSON.stringify({
    version: STORED_VERSION,
    invitationId: credential.invitationId,
    secret: credential.secret,
  });
  return enqueueWrite(async () => {
    try {
      await SecureStore.setItemAsync(PENDING_INVITATION_KEY, value);
      unsavedCredential = null;
    } catch {
      unsavedCredential = { ...credential };
      // The newer link replaces any older stored proof, even when it cannot
      // be persisted itself.
      await deleteStored();
      console.warn(
        `[pending-invitation] SecureStore.setItemAsync failed for "${PENDING_INVITATION_KEY}"; the invitation will not survive an app restart.`,
      );
    }
  });
}

/** The pending proof, or `null`. Never rejects. */
export async function readPendingOrganizationInvitation(): Promise<OrganizationInvitationCredential | null> {
  await lastWrite;
  if (unsavedCredential !== null) return { ...unsavedCredential };

  let raw: string | null;
  try {
    raw = await SecureStore.getItemAsync(PENDING_INVITATION_KEY);
  } catch {
    return null;
  }
  if (raw === null) return null;

  const credential = parseStored(raw);
  if (credential === null) await deleteStored();
  return credential;
}

export async function hasPendingOrganizationInvitation(): Promise<boolean> {
  return (await readPendingOrganizationInvitation()) !== null;
}

/** Never rejects. */
export function clearPendingOrganizationInvitation(): Promise<void> {
  return enqueueWrite(async () => {
    unsavedCredential = null;
    await deleteStored();
  });
}

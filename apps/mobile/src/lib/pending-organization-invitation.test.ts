import * as SecureStore from 'expo-secure-store';

import {
  clearPendingOrganizationInvitation,
  hasPendingOrganizationInvitation,
  readPendingOrganizationInvitation,
  savePendingOrganizationInvitation,
} from '@/lib/pending-organization-invitation';

jest.mock('expo-secure-store', () => ({
  getItemAsync: jest.fn(),
  setItemAsync: jest.fn(),
  deleteItemAsync: jest.fn(),
}));

const KEY = 'menizvet.pendingOrganizationInvitation.v1';
const ID = '3f2b6c1e-9a4d-4c3b-8e2f-1a2b3c4d5e6f';
const OTHER_ID = '7a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d';
const SECRET = 'cmVkYWN0ZWQtYnV0LXJlYWxpc3RpYy1zaGFwZWQtc2VjcmV0';

const store = new Map<string, string>();
const getItem = SecureStore.getItemAsync as jest.Mock;
const setItem = SecureStore.setItemAsync as jest.Mock;
const deleteItem = SecureStore.deleteItemAsync as jest.Mock;

beforeEach(async () => {
  store.clear();
  getItem.mockReset().mockImplementation(async (key: string) => store.get(key) ?? null);
  setItem.mockReset().mockImplementation(async (key: string, value: string) => {
    store.set(key, value);
  });
  deleteItem.mockReset().mockImplementation(async (key: string) => {
    store.delete(key);
  });
  await clearPendingOrganizationInvitation();
  deleteItem.mockClear();
});

describe('pending Organization Invitation proof', () => {
  it('saves only the versioned { invitationId, secret } under its own key and restores it', async () => {
    await savePendingOrganizationInvitation({ invitationId: ID, secret: SECRET });

    expect(setItem).toHaveBeenCalledTimes(1);
    expect(setItem.mock.calls[0][0]).toBe(KEY);
    expect(JSON.parse(setItem.mock.calls[0][1])).toEqual({
      version: 1,
      invitationId: ID,
      secret: SECRET,
    });
    await expect(readPendingOrganizationInvitation()).resolves.toEqual({
      invitationId: ID,
      secret: SECRET,
    });
    await expect(hasPendingOrganizationInvitation()).resolves.toBe(true);
  });

  it('a newer link replaces the older proof', async () => {
    await savePendingOrganizationInvitation({ invitationId: ID, secret: SECRET });
    await savePendingOrganizationInvitation({ invitationId: OTHER_ID, secret: 'b3RoZXI' });

    await expect(readPendingOrganizationInvitation()).resolves.toEqual({
      invitationId: OTHER_ID,
      secret: 'b3RoZXI',
    });
  });

  it('a read issued right after a save sees that save', async () => {
    void savePendingOrganizationInvitation({ invitationId: ID, secret: SECRET });
    await expect(readPendingOrganizationInvitation()).resolves.toEqual({
      invitationId: ID,
      secret: SECRET,
    });
  });

  it.each([
    ['malformed JSON', '{not json'],
    ['a stale version', JSON.stringify({ version: 0, invitationId: ID, secret: SECRET })],
    ['a future version', JSON.stringify({ version: 2, invitationId: ID, secret: SECRET })],
    ['a missing secret', JSON.stringify({ version: 1, invitationId: ID })],
    ['a malformed secret', JSON.stringify({ version: 1, invitationId: ID, secret: 'a b' })],
    ['a malformed id', JSON.stringify({ version: 1, invitationId: 'x', secret: SECRET })],
    ['an array', '[]'],
  ])('clears and ignores %s', async (_label, raw) => {
    store.set(KEY, raw);

    await expect(readPendingOrganizationInvitation()).resolves.toBeNull();
    expect(deleteItem).toHaveBeenCalledWith(KEY);
    expect(store.has(KEY)).toBe(false);
  });

  it('treats an unreadable keystore as no pending proof', async () => {
    getItem.mockRejectedValueOnce(new Error('keystore unavailable'));
    await expect(readPendingOrganizationInvitation()).resolves.toBeNull();
  });

  it('keeps the proof in memory when the keystore write fails, drops any older one, and never logs the secret', async () => {
    store.set(KEY, JSON.stringify({ version: 1, invitationId: OTHER_ID, secret: 'b2xkZXI' }));
    setItem.mockRejectedValueOnce(new Error('write failed'));
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => {});

    await savePendingOrganizationInvitation({ invitationId: ID, secret: SECRET });

    await expect(readPendingOrganizationInvitation()).resolves.toEqual({
      invitationId: ID,
      secret: SECRET,
    });
    expect(store.has(KEY)).toBe(false);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(warn.mock.calls)).not.toContain(SECRET);
    expect(JSON.stringify(warn.mock.calls)).not.toContain(ID);
    warn.mockRestore();

    await clearPendingOrganizationInvitation();
    await expect(readPendingOrganizationInvitation()).resolves.toBeNull();
  });

  it('clearing removes the stored proof and never rejects', async () => {
    await savePendingOrganizationInvitation({ invitationId: ID, secret: SECRET });
    await clearPendingOrganizationInvitation();
    expect(store.has(KEY)).toBe(false);

    deleteItem.mockRejectedValueOnce(new Error('delete failed'));
    await expect(clearPendingOrganizationInvitation()).resolves.toBeUndefined();
  });
});

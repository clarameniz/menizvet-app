import * as SecureStore from 'expo-secure-store';

import { generateInstallationId, getInstallationId } from '@/lib/installation-id';

jest.mock('expo-secure-store', () => ({
  getItemAsync: jest.fn(),
  setItemAsync: jest.fn(),
}));

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

const mockedGetItemAsync = SecureStore.getItemAsync as jest.Mock;
const mockedSetItemAsync = SecureStore.setItemAsync as jest.Mock;

beforeEach(() => {
  mockedGetItemAsync.mockReset();
  mockedSetItemAsync.mockReset();
});

describe('generateInstallationId', () => {
  it('produces a valid-shaped id', () => {
    expect(generateInstallationId()).toMatch(UUID_PATTERN);
  });

  it('produces different ids on repeated calls', () => {
    const ids = new Set(Array.from({ length: 20 }, () => generateInstallationId()));
    expect(ids.size).toBe(20);
  });
});

describe('getInstallationId', () => {
  it('reuses the persisted id when one already exists', async () => {
    mockedGetItemAsync.mockResolvedValue('existing-id');

    const result = await getInstallationId();

    expect(result).toBe('existing-id');
    expect(mockedSetItemAsync).not.toHaveBeenCalled();
  });

  it('generates and persists a new id when none exists', async () => {
    mockedGetItemAsync.mockResolvedValue(null);
    mockedSetItemAsync.mockResolvedValue(undefined);

    const result = await getInstallationId();

    expect(result).toMatch(UUID_PATTERN);
    expect(mockedSetItemAsync).toHaveBeenCalledWith('menizvet.pushInstallationId', result);
  });

  it('still returns a generated id when persistence fails', async () => {
    mockedGetItemAsync.mockResolvedValue(null);
    mockedSetItemAsync.mockRejectedValue(new Error('Keystore unavailable'));
    const warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});

    const result = await getInstallationId();

    expect(result).toMatch(UUID_PATTERN);
    warnSpy.mockRestore();
  });
});

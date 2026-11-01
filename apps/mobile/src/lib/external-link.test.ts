import { Linking } from 'react-native';

import { DELETE_ACCOUNT_URL, openExternalUrl, PRIVACY_POLICY_URL } from '@/lib/external-link';

const openURLSpy = jest.spyOn(Linking, 'openURL');

beforeEach(() => {
  openURLSpy.mockReset();
});

afterAll(() => {
  openURLSpy.mockRestore();
});

describe('openExternalUrl', () => {
  it('opens the given URL and reports success', async () => {
    openURLSpy.mockResolvedValue(true);

    await expect(openExternalUrl(PRIVACY_POLICY_URL)).resolves.toBe(true);
    expect(openURLSpy).toHaveBeenCalledWith(PRIVACY_POLICY_URL);
  });

  it('reports failure instead of throwing when the URL cannot be opened', async () => {
    openURLSpy.mockRejectedValue(new Error('No Activity found to handle Intent'));

    await expect(openExternalUrl(DELETE_ACCOUNT_URL)).resolves.toBe(false);
  });
});

describe('public account page URLs', () => {
  it('point to the public MenizVet pages over https', () => {
    expect(PRIVACY_POLICY_URL).toBe('https://menizvet.com/privacy');
    expect(DELETE_ACCOUNT_URL).toBe('https://menizvet.com/delete-account');
  });
});
